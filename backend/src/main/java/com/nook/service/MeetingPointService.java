package com.nook.service;

import com.nook.domain.SocialEntities.Match;
import com.nook.domain.SocialEntities.UserLocation;
import com.nook.dto.ApiDtos.GeoPointDto;
import com.nook.exception.ApiException;
import com.nook.repository.SocialRepository;
import java.util.UUID;
import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class MeetingPointService {
  private final SocialRepository repository;
  private final GeographicCalculator calculator;

  public MeetingPointService(SocialRepository repository, GeographicCalculator calculator) {
    this.repository = repository;
    this.calculator = calculator;
  }

  public GeoPointDto midpoint(UUID matchId, UUID requesterId) {
    Match match = repository.find(Match.class, matchId);
    if (match == null || !match.active
        || (!requesterId.equals(match.userOneId) && !requesterId.equals(match.userTwoId))
        || repository.blocked(match.userOneId, match.userTwoId)) {
      throw new ApiException(HttpStatus.NOT_FOUND, "MATCH_NOT_FOUND", "Match no encontrado");
    }
    UserLocation firstLocation=repository.location(match.userOneId),secondLocation=repository.location(match.userTwoId);
    Instant oldestAccepted = Instant.now().minusSeconds(86_400);
    if (firstLocation == null || secondLocation == null
        || firstLocation.capturedAt == null || secondLocation.capturedAt == null
        || firstLocation.capturedAt.isBefore(oldestAccepted)
        || secondLocation.capturedAt.isBefore(oldestAccepted)) {
      throw new ApiException(HttpStatus.CONFLICT, "LOCATION_INCOMPLETE", "Falta una ubicación aproximada");
    }
    GeographicCalculator.Point point = calculator.midpoint(
        firstLocation.latitude, firstLocation.longitude,
        secondLocation.latitude, secondLocation.longitude);
    return new GeoPointDto(point.latitude(), point.longitude());
  }
}
