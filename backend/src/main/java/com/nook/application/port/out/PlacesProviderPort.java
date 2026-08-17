package com.nook.application.port.out;

import com.nook.domain.SocialEntities.CoffeeShop;
import java.util.List;

public interface PlacesProviderPort {
  List<CoffeeShop> nearby(double latitude, double longitude, double radiusKm);
}
