package com.nook.service;

import static com.nook.domain.SocialEntities.*;

import com.nook.dto.ApiDtos.CreateDate;
import com.nook.dto.ApiDtos.DateDto;
import com.nook.dto.ApiDtos.UpdateDate;
import com.nook.application.port.out.PushNotificationPort;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;

@Service
public class CoffeeDateService {
  private final SocialRepository repo;
  private final SocialMapper mapper;
  private final AuditService audit;
  private final PushNotificationPort push;

  public CoffeeDateService(SocialRepository repo, SocialMapper mapper, AuditService audit, PushNotificationPort push) {
    this.repo = repo;
    this.mapper = mapper;
    this.audit = audit;
    this.push = push;
  }

  @Transactional
  public DateDto create(UUID me, CreateDate request) {
    CoffeeDateProposal previous=repo.dateByIdempotencyKey(me,request.idempotencyKey()).orElse(null);
    if(previous!=null)return dto(previous,me);
    if (!repo.matchMember(request.matchId(), me)) {
      throw new ApiException(HttpStatus.FORBIDDEN, "MATCH_REQUIRED", "La propuesta requiere un match");
    }
    Match match = repo.find(Match.class, request.matchId());
    repo.lock(match);
    // A concurrent retry may have committed while this request waited for the match lock.
    previous=repo.dateByIdempotencyKey(me,request.idempotencyKey()).orElse(null);
    if(previous!=null)return dto(previous,me);
    if (request.proposedAt().isBefore(Instant.now())) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "PAST_DATE", "La propuesta debe ser futura");
    }
    if (repo.activeDate(request.matchId()).isPresent()) {
      throw new ApiException(HttpStatus.CONFLICT, "ACTIVE_PROPOSAL_EXISTS", "Ya existe una propuesta activa para este match");
    }
    CoffeeShop shop = repo.find(CoffeeShop.class, request.coffeeShopId());
    if (shop == null) {
      throw new ApiException(HttpStatus.NOT_FOUND, "SHOP_NOT_FOUND", "Cafetería no encontrada");
    }
    CoffeeDateProposal proposal = new CoffeeDateProposal();
    proposal.senderId = me;
    proposal.receiverId = match.userOneId.equals(me) ? match.userTwoId : match.userOneId;
    proposal.matchId = request.matchId();
    proposal.coffeeShopId = shop.id;
    proposal.idempotencyKey = request.idempotencyKey();
    proposal.coffeeShopSnapshot = snapshot(shop);
    proposal.proposedAt = request.proposedAt();
    proposal.paymentPreference = request.paymentPreference();
    proposal.nookChoice = request.nookChoice();
    repo.save(proposal);
    audit.record(me, "PROPOSAL_CREATED", "COFFEE_PROPOSAL", proposal.id);
    notify(proposal.receiverId, proposal, repo.profile(me).name + " te propone un café ☕");
    return dto(proposal, me);
  }

  @Transactional
  public DateDto transition(UUID me, UUID id, DateStatus next) {
    CoffeeDateProposal proposal = participant(me, id);
    if (proposal.status != DateStatus.PENDING && proposal.status != DateStatus.COUNTER_PROPOSED) {
      throw new ApiException(HttpStatus.CONFLICT, "PROPOSAL_NOT_ACTIVE", "La propuesta ya no está pendiente");
    }
    if ((next == DateStatus.ACCEPTED || next == DateStatus.DECLINED) && !proposal.receiverId.equals(me)) {
      throw new ApiException(HttpStatus.FORBIDDEN, "ONLY_RECIPIENT_RESPONDS", "Solo quien recibe puede responder");
    }
    if (next == DateStatus.COMPLETED) {
      throw new ApiException(HttpStatus.CONFLICT, "ACCEPTED_REQUIRED", "Primero hay que confirmar el café");
    }
    proposal.status = next;
    proposal.updatedAt = Instant.now();
    if (next == DateStatus.ACCEPTED) {
      proposal.acceptedAt = proposal.updatedAt;
      addCoffeeEvent(proposal, "COFFEE_ACCEPTED", "TENEMOS UN CAFÉ PENDIENTE");
    }
    if(next==DateStatus.ACCEPTED)audit.record(me,"PROPOSAL_ACCEPTED","COFFEE_PROPOSAL",proposal.id);
    if(next==DateStatus.DECLINED)audit.record(me,"PROPOSAL_REJECTED","COFFEE_PROPOSAL",proposal.id);
    notify(other(me, proposal), proposal, next == DateStatus.ACCEPTED ? "CAFÉ CONFIRMADO ☕" : "Propuesta actualizada");
    return dto(proposal, me);
  }

  @Transactional
  public DateDto complete(UUID me, UUID id) {
    CoffeeDateProposal proposal = participant(me, id);
    if (proposal.status != DateStatus.ACCEPTED) {
      throw new ApiException(HttpStatus.CONFLICT, "ACCEPTED_REQUIRED", "Solo se puede completar un café confirmado");
    }
    proposal.status = DateStatus.COMPLETED;
    proposal.completedAt = proposal.updatedAt = Instant.now();
    addCoffeeEvent(proposal, "COFFEE_COMPLETED", "CAFÉ COMPLETADO");
    return dto(proposal, me);
  }

  @Transactional
  public DateDto update(UUID me, UUID id, UpdateDate request) {
    CoffeeDateProposal proposal = participant(me, id);
    if (request.status() != null) {
      return request.status() == DateStatus.COMPLETED
          ? complete(me, id) : transition(me, id, request.status());
    }
    if (proposal.status != DateStatus.PENDING && proposal.status != DateStatus.COUNTER_PROPOSED) {
      throw new ApiException(HttpStatus.CONFLICT, "PROPOSAL_NOT_ACTIVE", "La propuesta ya no está pendiente");
    }
    boolean counterProposal = request.proposedAt() != null || request.coffeeShopId() != null;
    if (request.proposedAt() != null) {
      if (request.proposedAt().isBefore(Instant.now())) throw new ApiException(HttpStatus.BAD_REQUEST, "PAST_DATE", "La propuesta debe ser futura");
      proposal.proposedAt = request.proposedAt();
      proposal.status = DateStatus.COUNTER_PROPOSED;
    }
    if (request.coffeeShopId() != null) {
      CoffeeShop shop = repo.find(CoffeeShop.class, request.coffeeShopId());
      if (shop == null) throw new ApiException(HttpStatus.NOT_FOUND, "SHOP_NOT_FOUND", "Cafetería no encontrada");
      proposal.coffeeShopId = shop.id;
      proposal.coffeeShopSnapshot = snapshot(shop);
      proposal.status = DateStatus.COUNTER_PROPOSED;
    }
    if (request.paymentPreference() != null) proposal.paymentPreference = request.paymentPreference();
    if (counterProposal && !proposal.senderId.equals(me)) {
      UUID previousSender = proposal.senderId;
      proposal.senderId = me;
      proposal.receiverId = previousSender;
    }
    proposal.updatedAt = Instant.now();
    if (counterProposal) {
      audit.record(me, "PROPOSAL_COUNTERED", "COFFEE_PROPOSAL", proposal.id);
      notify(proposal.receiverId, proposal, repo.profile(me).name + " ha cambiado la propuesta");
    }
    return dto(proposal, me);
  }

  @Transactional
  public List<DateDto> list(UUID me) {
    completeExpiredAcceptedDates();
    return repo.dates(me).stream().map(d -> dto(d, me)).toList();
  }

  public DateDto get(UUID me, UUID id) {
    CoffeeDateProposal proposal = repo.find(CoffeeDateProposal.class, id);
    if (proposal == null || (!proposal.senderId.equals(me) && !proposal.receiverId.equals(me))) {
      throw new ApiException(HttpStatus.NOT_FOUND, "DATE_NOT_FOUND", "Propuesta no encontrada");
    }
    return dto(proposal, me);
  }

  @Transactional
  @Scheduled(fixedDelayString="${nook.coffee-completion-interval-ms:3600000}")
  public void completeExpiredAcceptedDates() {
    Instant now=Instant.now();
    repo.acceptedDatesBefore(now.minusSeconds(86_400)).forEach(d->{
      d.status=DateStatus.COMPLETED;d.completedAt=d.updatedAt=now;
      addCoffeeEvent(d,"COFFEE_COMPLETED","CAFÉ COMPLETADO");
      audit.record(null,"PROPOSAL_COMPLETED","COFFEE_PROPOSAL",d.id);
    });
  }

  private CoffeeDateProposal participant(UUID me, UUID id) {
    CoffeeDateProposal proposal = repo.find(CoffeeDateProposal.class, id);
    if (proposal == null || (!proposal.senderId.equals(me) && !proposal.receiverId.equals(me))) {
      throw new ApiException(HttpStatus.NOT_FOUND, "DATE_NOT_FOUND", "Propuesta no encontrada");
    }
    repo.lock(proposal);
    Match match = repo.find(Match.class, proposal.matchId);
    if (match == null || !match.active || repo.blocked(proposal.senderId, proposal.receiverId)) {
      throw new ApiException(HttpStatus.FORBIDDEN, "MATCH_INACTIVE", "Esta conexión ya no está activa");
    }
    return proposal;
  }

  private void addCoffeeEvent(CoffeeDateProposal proposal, String type, String body) {
    Conversation conversation = repo.conversationByMatch(proposal.matchId);
    Message message = new Message();
    message.conversationId = conversation.id;
    message.senderId = null;
    message.messageType = type;
    message.body = body;
    message.metadata = "{\"coffeeDateId\":\"" + proposal.id + "\"}";
    repo.save(message);
    conversation.updatedAt = Instant.now();
  }

  private String snapshot(CoffeeShop shop) {
    return "{\"providerId\":\"" + json(shop.providerId) + "\",\"name\":\"" + json(shop.name)
        + "\",\"address\":\"" + json(shop.address) + "\"}";
  }

  private String json(String value) { return value == null ? "" : value.replace("\\", "\\\\").replace("\"", "\\\""); }
  private UUID other(UUID me, CoffeeDateProposal d) { return d.senderId.equals(me) ? d.receiverId : d.senderId; }
  private DateDto dto(CoffeeDateProposal d, UUID me) {
    Profile profile = repo.profile(me);
    return new DateDto(d.id, d.matchId, d.senderId, d.receiverId,
        mapper.shop(repo.find(CoffeeShop.class, d.coffeeShopId), profile.latitude == null ? 0 : profile.latitude,
            profile.longitude == null ? 0 : profile.longitude), d.proposedAt, d.paymentPreference, d.status, d.createdAt, d.nookChoice);
  }
  private void notify(UUID user, CoffeeDateProposal d, String title) {
    push.deliver(user,d.status == DateStatus.ACCEPTED ? "COFFEE_ACCEPTED" : "COFFEE_PROPOSAL",
        title,repo.find(CoffeeShop.class,d.coffeeShopId).name,d.id);
  }
}
