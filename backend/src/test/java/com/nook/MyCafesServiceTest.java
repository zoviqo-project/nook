package com.nook;

import static com.nook.domain.SocialEntities.*;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

import com.nook.dto.ApiDtos.*;
import com.nook.service.*;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;

class MyCafesServiceTest {
  private final DiscoveryService discovery = mock(DiscoveryService.class);
  private final CoffeeDateService dates = mock(CoffeeDateService.class);
  private final MyCafesService service = new MyCafesService(discovery, dates);

  @Test void returnsOneCompleteCardForMatchWithoutProposal() {
    UUID me=UUID.randomUUID(),match=UUID.randomUUID(),conversation=UUID.randomUUID();
    when(discovery.matches(me)).thenReturn(List.of(new MatchDto(match,person(),Instant.now(),conversation)));
    when(dates.list(me)).thenReturn(List.of());
    MyCafeDto item=service.list(me).get(0);
    assertThat(item.matchId()).isEqualTo(match);
    assertThat(item.person().photos()).isNotEmpty();
    assertThat(item.proposal()).isNull();
    assertThat(item.availableActions()).containsExactly("PROPOSE","CHAT");
  }

  @Test void choosesActiveProposalAndExposesReceiverActionsWithoutDuplicates() {
    UUID me=UUID.randomUUID(),sender=UUID.randomUUID(),match=UUID.randomUUID();
    when(discovery.matches(me)).thenReturn(List.of(new MatchDto(match,person(),Instant.now(),UUID.randomUUID())));
    DateDto cancelled=date(match,sender,me,DateStatus.CANCELLED,Instant.now().minusSeconds(100));
    DateDto pending=date(match,sender,me,DateStatus.PENDING,Instant.now());
    when(dates.list(me)).thenReturn(List.of(cancelled,pending));
    List<MyCafeDto> result=service.list(me);
    assertThat(result).hasSize(1);
    assertThat(result.get(0).proposal().id()).isEqualTo(pending.id());
    assertThat(result.get(0).availableActions()).containsExactly("ACCEPT","DECLINE","CHAT");
  }

  private DiscoverProfile person(){return new DiscoverProfile(UUID.randomUUID(),"Marta",27,"Bio","Madrid",1.0,"Latte",null,null,2,null,LookingFor.MEET_PEOPLE,List.of("LATTE"),List.of(new PhotoDto(UUID.randomUUID(),"/photo",0,true)),null);}
  private DateDto date(UUID match,UUID sender,UUID receiver,DateStatus status,Instant created){
    ShopDto shop=new ShopDto(UUID.randomUUID(),"Cafetería","Dirección",null,1.0,"/cafe",null,null,null,List.of(),null,null,null,null,null,null,null,null,null,List.of(),List.of(),null);
    return new DateDto(UUID.randomUUID(),match,sender,receiver,shop,Instant.now().plusSeconds(3600),PaymentPreference.SPLIT,status,created,false,"UTC");
  }
}
