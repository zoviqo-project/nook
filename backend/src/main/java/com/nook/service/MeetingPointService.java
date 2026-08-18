package com.nook.service;

import com.nook.domain.SocialEntities.Match;
import com.nook.domain.SocialEntities.User;
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
    User firstUser = repository.user(match.userOneId), secondUser = repository.user(match.userTwoId);
    boolean requesterIsFirst = requesterId.equals(match.userOneId);
    UserLocation requesterLocation = requesterIsFirst ? firstLocation : secondLocation;
    UUID otherId = requesterIsFirst ? match.userTwoId : match.userOneId;
    User otherUser = requesterIsFirst ? secondUser : firstUser;
    if (isDemo(otherUser) && requesterLocation != null) {
      if (requesterIsFirst) secondLocation = demoLocationNear(requesterLocation, otherId);
      else firstLocation = demoLocationNear(requesterLocation, otherId);
    } else if (isDemo(requesterIsFirst ? firstUser : secondUser)) {
      UserLocation realLocation = requesterIsFirst ? secondLocation : firstLocation;
      if (realLocation != null) {
        if (requesterIsFirst) firstLocation = demoLocationNear(realLocation, requesterId);
        else secondLocation = demoLocationNear(realLocation, requesterId);
      }
    }
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

  private boolean isDemo(User user) {
    return user != null && user.email != null && user.email.toLowerCase().endsWith("@nook.demo");
  }

  private UserLocation demoLocationNear(UserLocation anchor, UUID demoId) {
    double direction = (demoId.hashCode() & 1) == 0 ? 1d : -1d;
    double latitude = Math.max(-89.8, Math.min(89.8, anchor.latitude + direction * 0.018));
    double longitudeScale = Math.max(0.2, Math.cos(Math.toRadians(anchor.latitude)));
    double longitude = anchor.longitude + direction * 0.018 / longitudeScale;
    if (longitude > 180) longitude -= 360;
    if (longitude < -180) longitude += 360;
    UserLocation location = new UserLocation();
    location.latitude = latitude;
    location.longitude = longitude;
    location.accuracyMeters = 100d;
    location.capturedAt = Instant.now();
    return location;
  }
}
