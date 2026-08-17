package com.nook;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.nook.domain.SocialEntities.Match;
import com.nook.domain.SocialEntities.UserLocation;
import com.nook.repository.SocialRepository;
import com.nook.service.GeographicCalculator;
import com.nook.service.MeetingPointService;
import java.util.UUID;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MeetingPointServiceTest {
  @Mock SocialRepository repository;

  @Test
  void calculatesMidpointWithoutReturningEitherUsersLocation() {
    UUID matchId = UUID.randomUUID();
    UUID firstId = UUID.randomUUID();
    UUID secondId = UUID.randomUUID();
    Match match = new Match();
    match.id = matchId;
    match.userOneId = firstId;
    match.userTwoId = secondId;
    UserLocation first = new UserLocation();
    first.latitude = 41.3936;
    first.longitude = 2.0093;
    first.capturedAt = Instant.now();
    UserLocation second = new UserLocation();
    second.latitude = 41.3874;
    second.longitude = 2.1686;
    second.capturedAt = Instant.now();
    when(repository.find(Match.class, matchId)).thenReturn(match);
    when(repository.location(firstId)).thenReturn(first);
    when(repository.location(secondId)).thenReturn(second);

    var result = new MeetingPointService(repository, new GeographicCalculator())
        .midpoint(matchId, firstId);

    assertThat(result.latitude()).isBetween(41.38, 41.41);
    assertThat(result.longitude()).isBetween(2.07, 2.10);
    assertThat(result.longitude()).isNotEqualTo(first.longitude).isNotEqualTo(second.longitude);
  }
}
