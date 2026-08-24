package com.nook;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

import com.nook.application.port.out.PushNotificationPort;
import com.nook.domain.SocialEntities.Match;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import com.nook.service.*;
import jakarta.persistence.EntityManager;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.core.env.Environment;

class DiscoveryServiceTest {
  private final SocialRepository repository=mock(SocialRepository.class);
  private final EntityManager entityManager=mock(EntityManager.class);
  private final DiscoveryService service=new DiscoveryService(
      repository,mock(SocialMapper.class),entityManager,mock(PushNotificationPort.class),
      new AuditService(repository),mock(Environment.class));

  @Test void deletingMatchCancelsOngoingDatesAndRecordsAudit(){
    UUID me=UUID.randomUUID();
    Match match=new Match();match.id=UUID.randomUUID();match.userOneId=me;match.userTwoId=UUID.randomUUID();
    match.active=true;
    when(repository.find(Match.class,match.id)).thenReturn(match);

    service.deleteMatch(me,match.id);

    verify(repository).lock(match);
    verify(repository).cancelOngoingDatesForMatch(match.id);
    verify(repository).save(argThat(value -> value instanceof com.nook.domain.SocialEntities.AuditEvent));
    org.assertj.core.api.Assertions.assertThat(match.active).isFalse();
  }

  @Test void nonParticipantCannotDeleteMatch(){
    UUID me=UUID.randomUUID();
    Match match=new Match();match.id=UUID.randomUUID();match.userOneId=UUID.randomUUID();
    match.userTwoId=UUID.randomUUID();
    when(repository.find(Match.class,match.id)).thenReturn(match);

    assertThatThrownBy(()->service.deleteMatch(me,match.id)).isInstanceOf(ApiException.class);
    verify(repository,never()).cancelOngoingDatesForMatch(any());
  }
}
