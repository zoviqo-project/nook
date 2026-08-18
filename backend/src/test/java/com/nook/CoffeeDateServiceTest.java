package com.nook;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.nook.domain.SocialEntities.*;
import com.nook.dto.ApiDtos.CreateDate;
import com.nook.dto.ApiDtos.UpdateDate;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import com.nook.service.*;
import com.nook.application.port.out.PushNotificationPort;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CoffeeDateServiceTest {
  @Mock SocialRepository repository;
  @Mock SocialMapper mapper;
  @Mock PushNotificationPort push;

  private CoffeeDateService service(){return new CoffeeDateService(repository,mapper,new AuditService(repository),push);}

  @Test void onlyMatchParticipantsCanCreateAProposal(){
    UUID user=UUID.randomUUID(),match=UUID.randomUUID();
    when(repository.matchMember(match,user)).thenReturn(false);
    var request=new CreateDate(match,UUID.randomUUID(),Instant.now().plusSeconds(3600),PaymentPreference.SPLIT,false,UUID.randomUUID(),"Europe/Madrid");
    assertThatThrownBy(()->service().create(user,request)).isInstanceOf(ApiException.class)
        .hasMessageContaining("match");
  }

  @Test void onlyRecipientCanAcceptPendingProposal(){
    UUID sender=UUID.randomUUID();
    CoffeeDateProposal proposal=new CoffeeDateProposal();proposal.id=UUID.randomUUID();proposal.senderId=sender;
    proposal.receiverId=UUID.randomUUID();proposal.status=DateStatus.PENDING;proposal.matchId=UUID.randomUUID();
    Match match=new Match();match.id=proposal.matchId;match.active=true;
    when(repository.find(CoffeeDateProposal.class,proposal.id)).thenReturn(proposal);
    when(repository.find(Match.class,proposal.matchId)).thenReturn(match);
    assertThatThrownBy(()->service().transition(sender,proposal.id,DateStatus.ACCEPTED))
        .isInstanceOf(ApiException.class).hasMessageContaining("recibe");
  }

  @Test void acceptedProposalCannotBeAcceptedTwice(){
    UUID recipient=UUID.randomUUID();
    CoffeeDateProposal proposal=new CoffeeDateProposal();proposal.id=UUID.randomUUID();proposal.senderId=UUID.randomUUID();
    proposal.receiverId=recipient;proposal.status=DateStatus.ACCEPTED;proposal.matchId=UUID.randomUUID();
    Match match=new Match();match.id=proposal.matchId;match.active=true;
    when(repository.find(CoffeeDateProposal.class,proposal.id)).thenReturn(proposal);
    when(repository.find(Match.class,proposal.matchId)).thenReturn(match);
    assertThatThrownBy(()->service().transition(recipient,proposal.id,DateStatus.ACCEPTED))
        .isInstanceOf(ApiException.class).hasMessageContaining("no está pendiente");
  }

  @Test void eitherParticipantCanCancelAnAcceptedCoffee(){
    UUID sender=UUID.randomUUID();
    CoffeeDateProposal proposal=new CoffeeDateProposal();proposal.id=UUID.randomUUID();proposal.senderId=sender;
    proposal.receiverId=UUID.randomUUID();proposal.status=DateStatus.ACCEPTED;proposal.matchId=UUID.randomUUID();
    proposal.coffeeShopId=UUID.randomUUID();
    Match match=new Match();match.id=proposal.matchId;match.active=true;
    CoffeeShop shop=new CoffeeShop();shop.id=proposal.coffeeShopId;shop.name="Tempo";
    Conversation conversation=new Conversation();conversation.id=UUID.randomUUID();
    Profile profile=new Profile();
    when(repository.find(CoffeeDateProposal.class,proposal.id)).thenReturn(proposal);
    when(repository.find(Match.class,proposal.matchId)).thenReturn(match);
    when(repository.find(CoffeeShop.class,proposal.coffeeShopId)).thenReturn(shop);
    when(repository.profile(sender)).thenReturn(profile);
    when(repository.conversationByMatch(proposal.matchId)).thenReturn(conversation);

    service().transition(sender,proposal.id,DateStatus.CANCELLED);

    assertThat(proposal.status).isEqualTo(DateStatus.CANCELLED);
    verify(repository).save(argThat(value->value instanceof Message message
        && "COFFEE_CANCELLED".equals(message.messageType)));
  }

  @Test void schedulerCompletesAcceptedCoffeeAfterTwentyFourHoursOnlyOnce(){
    CoffeeDateProposal proposal=new CoffeeDateProposal();proposal.id=UUID.randomUUID();
    proposal.status=DateStatus.ACCEPTED;proposal.proposedAt=Instant.now().minusSeconds(90_000);
    proposal.matchId=UUID.randomUUID();
    Conversation conversation=new Conversation();conversation.id=UUID.randomUUID();
    when(repository.acceptedDatesBefore(any())).thenReturn(List.of(proposal));
    when(repository.conversationByMatch(proposal.matchId)).thenReturn(conversation);

    service().completeExpiredAcceptedDates();

    assertThat(proposal.status).isEqualTo(DateStatus.COMPLETED);
    assertThat(proposal.completedAt).isNotNull();
    verify(repository).save(argThat(value->value instanceof Message message&&"COFFEE_COMPLETED".equals(message.messageType)));
  }

  @Test void repeatedIdempotencyKeyReturnsExistingProposalWithoutSavingAnother(){
    UUID user=UUID.randomUUID(),key=UUID.randomUUID();
    CoffeeDateProposal proposal=new CoffeeDateProposal();proposal.id=UUID.randomUUID();proposal.senderId=user;
    proposal.receiverId=UUID.randomUUID();proposal.matchId=UUID.randomUUID();proposal.coffeeShopId=UUID.randomUUID();
    proposal.proposedAt=Instant.now().plusSeconds(3600);proposal.paymentPreference=PaymentPreference.SPLIT;
    CoffeeShop shop=new CoffeeShop();shop.id=proposal.coffeeShopId;Profile profile=new Profile();
    when(repository.dateByIdempotencyKey(user,key)).thenReturn(Optional.of(proposal));
    when(repository.profile(user)).thenReturn(profile);when(repository.find(CoffeeShop.class,proposal.coffeeShopId)).thenReturn(shop);
    var request=new CreateDate(proposal.matchId,proposal.coffeeShopId,proposal.proposedAt,PaymentPreference.SPLIT,false,key,"America/New_York");

    var result=service().create(user,request);

    assertThat(result.id()).isEqualTo(proposal.id);verify(repository,never()).save(any());
  }

  @Test void invalidIanaTimeZoneIsRejected(){
    UUID user=UUID.randomUUID(),matchId=UUID.randomUUID(),shopId=UUID.randomUUID();
    Match match=new Match();match.id=matchId;match.userOneId=user;match.userTwoId=UUID.randomUUID();
    CoffeeShop shop=new CoffeeShop();shop.id=shopId;
    when(repository.matchMember(matchId,user)).thenReturn(true);
    when(repository.find(Match.class,matchId)).thenReturn(match);
    when(repository.find(CoffeeShop.class,shopId)).thenReturn(shop);
    doAnswer(invocation->{CoffeeDateProposal value=invocation.getArgument(0);value.id=UUID.randomUUID();return value;})
        .when(repository).save(any(CoffeeDateProposal.class));
    var request=new CreateDate(matchId,shopId,Instant.now().plusSeconds(3600),PaymentPreference.SPLIT,
        false,UUID.randomUUID(),"Not/A_Time_Zone");

    assertThatThrownBy(()->service().create(user,request)).isInstanceOf(ApiException.class)
        .hasMessageContaining("Zona horaria");
    verify(repository,never()).setDateTimeZone(any(),anyString());
  }

  @Test void recipientCounterProposalSwapsRolesSoOriginalSenderCanRespond(){
    UUID originalSender=UUID.randomUUID(),recipient=UUID.randomUUID();
    CoffeeDateProposal proposal=new CoffeeDateProposal();proposal.id=UUID.randomUUID();
    proposal.senderId=originalSender;proposal.receiverId=recipient;proposal.matchId=UUID.randomUUID();
    proposal.coffeeShopId=UUID.randomUUID();proposal.status=DateStatus.PENDING;
    proposal.proposedAt=Instant.now().plusSeconds(3_600);proposal.paymentPreference=PaymentPreference.SPLIT;
    Match match=new Match();match.id=proposal.matchId;match.active=true;
    CoffeeShop shop=new CoffeeShop();shop.id=proposal.coffeeShopId;shop.name="Nook Coffee";
    Profile recipientProfile=new Profile();recipientProfile.name="Laura";
    when(repository.find(CoffeeDateProposal.class,proposal.id)).thenReturn(proposal);
    when(repository.find(Match.class,proposal.matchId)).thenReturn(match);
    when(repository.find(CoffeeShop.class,proposal.coffeeShopId)).thenReturn(shop);
    when(repository.profile(recipient)).thenReturn(recipientProfile);

    service().update(recipient,proposal.id,new UpdateDate(
        null,Instant.now().plusSeconds(7_200),null,null));

    assertThat(proposal.senderId).isEqualTo(recipient);
    assertThat(proposal.receiverId).isEqualTo(originalSender);
    assertThat(proposal.status).isEqualTo(DateStatus.COUNTER_PROPOSED);
    verify(push).deliver(eq(originalSender),eq("COFFEE_PROPOSAL"),contains("cambiado"),
        eq("Nook Coffee"),eq(proposal.id));
  }
}
