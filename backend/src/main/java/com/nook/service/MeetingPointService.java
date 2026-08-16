package com.nook.service;

import com.nook.domain.SocialEntities.Match;
import com.nook.domain.SocialEntities.Profile;
import com.nook.domain.SocialEntities.UserLocation;
import com.nook.dto.ApiDtos.GeoPointDto;
import com.nook.exception.ApiException;
import com.nook.repository.SocialRepository;
import java.util.UUID;
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
        || (!requesterId.equals(match.userOneId) && !requesterId.equals(match.userTwoId))) {
      throw new ApiException(HttpStatus.NOT_FOUND, "MATCH_NOT_FOUND", "Match no encontrado");
    }
    Profile first = repository.profile(match.userOneId);
    Profile second = repository.profile(match.userTwoId);
    UserLocation firstLocation=repository.location(match.userOneId),secondLocation=repository.location(match.userTwoId);
    Double firstLatitude=firstLocation==null?first.latitude:firstLocation.latitude;
    Double firstLongitude=firstLocation==null?first.longitude:firstLocation.longitude;
    Double secondLatitude=secondLocation==null?second.latitude:secondLocation.latitude;
    Double secondLongitude=secondLocation==null?second.longitude:secondLocation.longitude;
    if (firstLatitude == null || firstLongitude == null
        || secondLatitude == null || secondLongitude == null) {
      throw new ApiException(HttpStatus.CONFLICT, "LOCATION_INCOMPLETE", "Falta una ubicación aproximada");
    }
    GeographicCalculator.Point point = calculator.midpoint(
        firstLatitude, firstLongitude, secondLatitude, secondLongitude);
    return new GeoPointDto(point.latitude(), point.longitude());
  }
}
