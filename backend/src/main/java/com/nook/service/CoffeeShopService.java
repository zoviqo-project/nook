package com.nook.service;

import com.nook.application.port.out.PlacesProviderPort;
import com.nook.domain.SocialEntities.CoffeeShop;
import com.nook.dto.ApiDtos.ShopDto;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class CoffeeShopService {
  private final PlacesProviderPort provider;
  private final SocialMapper mapper;
  private final SocialRepository repository;

  public CoffeeShopService(PlacesProviderPort provider, SocialMapper mapper, SocialRepository repository) {
    this.provider = provider;
    this.mapper = mapper;
    this.repository = repository;
  }

  public List<ShopDto> nearby(double latitude, double longitude, double radiusKm) {
    return provider.nearby(latitude, longitude, radiusKm).stream()
        .map(shop -> mapper.shop(shop, latitude, longitude))
        .filter(shop -> shop.distanceKm() <= radiusKm)
        .sorted(Comparator.comparingDouble(ShopDto::distanceKm))
        .toList();
  }

  public ShopDto one(UUID id, double latitude, double longitude) {
    CoffeeShop shop = repository.find(CoffeeShop.class, id);
    if (shop == null) {
      throw new ApiException(HttpStatus.NOT_FOUND, "SHOP_NOT_FOUND", "Cafetería no encontrada");
    }
    return mapper.shop(shop, latitude, longitude);
  }
}
