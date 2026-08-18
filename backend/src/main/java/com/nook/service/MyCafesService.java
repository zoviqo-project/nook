package com.nook.service;

import com.nook.domain.SocialEntities.DateStatus;
import com.nook.dto.ApiDtos.DateDto;
import com.nook.dto.ApiDtos.MatchDto;
import com.nook.dto.ApiDtos.MyCafeDto;
import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class MyCafesService {
  private final DiscoveryService discovery;
  private final CoffeeDateService dates;

  public MyCafesService(DiscoveryService discovery, CoffeeDateService dates) {
    this.discovery = discovery;
    this.dates = dates;
  }

  @Transactional
  public List<MyCafeDto> list(UUID me) {
    List<DateDto> allDates = dates.list(me);
    Map<UUID, DateDto> proposalByMatch = allDates.stream().collect(Collectors.toMap(
        DateDto::matchId, Function.identity(), this::preferred));
    return discovery.matches(me).stream().map(match -> {
      DateDto proposal = proposalByMatch.get(match.id());
      return new MyCafeDto(match.id(), match.person(), match.matchedAt(), match.conversationId(), proposal,
          actions(me, proposal));
    }).toList();
  }

  private DateDto preferred(DateDto left, DateDto right) {
    int comparison = Integer.compare(priority(left.status()), priority(right.status()));
    if (comparison != 0) return comparison > 0 ? left : right;
    return left.createdAt().isAfter(right.createdAt()) ? left : right;
  }

  private int priority(DateStatus status) {
    return switch (status) {
      case ACCEPTED -> 60;
      case PENDING, COUNTER_PROPOSED -> 50;
      case COMPLETED -> 40;
      case CANCELLED, DECLINED, EXPIRED -> 30;
    };
  }

  private List<String> actions(UUID me, DateDto proposal) {
    if (proposal == null) return List.of("PROPOSE", "CHAT");
    return switch (proposal.status()) {
      case PENDING, COUNTER_PROPOSED -> proposal.receiverId().equals(me)
          ? List.of("ACCEPT", "DECLINE", "CHAT") : List.of("CANCEL", "CHAT");
      case ACCEPTED -> List.of("DETAIL", "CHAT", "CANCEL", "COMPLETE");
      case COMPLETED -> List.of("DETAIL", "CHAT");
      case CANCELLED, DECLINED, EXPIRED -> List.of("PROPOSE", "CHAT");
    };
  }
}
