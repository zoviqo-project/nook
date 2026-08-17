package com.nook.service;

import com.nook.application.port.out.PlacePhotoPort;
import com.nook.application.port.out.PlacesProviderPort;
import com.nook.domain.SocialEntities.CoffeeShop;
import com.nook.repository.SocialRepository;
import java.util.List;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import com.nook.exception.ApiException;

@Component
@Profile("demo-seed")
public class SeedPlacesProvider implements PlacesProviderPort, PlacePhotoPort {
  private final SocialRepository repository;

  public SeedPlacesProvider(SocialRepository repository) { this.repository = repository; }

  @Override public List<CoffeeShop> nearby(double latitude, double longitude, double radiusKm) {
    return repository.shops();
  }

  @Override public PhotoAsset photo(String token) {
    throw new ApiException(HttpStatus.NOT_FOUND, "PLACE_PHOTO_NOT_FOUND", "Foto no disponible");
  }
}
