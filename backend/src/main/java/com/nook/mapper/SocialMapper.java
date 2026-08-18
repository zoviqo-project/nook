package com.nook.mapper;

import com.nook.domain.SocialEntities.*;
import com.nook.dto.ApiDtos.*;
import com.nook.repository.SocialRepository;
import java.time.LocalDate;
import java.time.Period;
import java.util.*;
import org.springframework.stereotype.Component;

@Component
public class SocialMapper {
  private final SocialRepository repo;
  public SocialMapper(SocialRepository repo) { this.repo = repo; }

  public Integer age(LocalDate birthDate) {
    return birthDate == null ? null : Period.between(birthDate, LocalDate.now()).getYears();
  }
  public PhotoDto photo(Photo value) {
    return new PhotoDto(value.id, value.url, value.position, value.primary);
  }
  public List<String> split(String value) {
    return value == null || value.isBlank() ? List.of()
        : Arrays.stream(value.split(",")).filter(item -> !item.isBlank()).toList();
  }
  public Me me(User user) {
    Profile profile = repo.profile(user.id);
    Preference preferences = repo.preference(user.id);
    return new Me(user.id, user.email, profile.name, age(profile.birthDate), profile.birthDate,
        profile.gender, profile.bio, profile.city, profile.lookingFor, profile.coffeePersonality,
        profile.preferredPlan, profile.preferredVibe, profile.coffeesPerDay,
        profile.favoriteCoffeeMoment, preferences.minAge, preferences.maxAge,
        preferences.maxDistanceKm, preferences.visible, user.hidden, profile.onboardingComplete,
        repo.coffees(user.id), repo.photos(user.id).stream().map(this::photo).toList(),
        split(preferences.desiredGenders), split(preferences.intentions),
        split(preferences.preferredVibes), split(preferences.preferredMoments),
        split(preferences.meetingStyles));
  }
  public DiscoverProfile profile(UUID viewer, Profile profile) {
    Profile me = repo.profile(viewer);
    Integer profileAge = age(profile.birthDate);
    if (profileAge == null || profile.lookingFor == null) {
      throw new IllegalStateException("Discover profile is incomplete");
    }
    return new DiscoverProfile(profile.userId, profile.name, profileAge, profile.bio, profile.city,
        distance(me.latitude, me.longitude, profile.latitude, profile.longitude),
        profile.coffeePersonality, profile.preferredPlan, profile.preferredVibe,
        profile.coffeesPerDay, profile.favoriteCoffeeMoment, profile.lookingFor,
        repo.coffees(profile.userId), repo.photos(profile.userId).stream().map(this::photo).toList());
  }
  public ShopDto shop(CoffeeShop shop, double latitude, double longitude) {
    return shop(shop,latitude,longitude,repo.vibes(shop.id));
  }
  public ShopDto shop(CoffeeShop shop, double latitude, double longitude,List<String> vibes) {
    return new ShopDto(shop.id, shop.name, shop.address, shop.neighborhood,
        distance(latitude, longitude, shop.latitude, shop.longitude), shop.photoUrl,
        shop.openingHours, shop.rating, shop.description, vibes, shop.latitude,
        shop.longitude, shop.providerId, shop.reviewCount, shop.openNow, shop.priceLevel,
        shop.website, shop.phone, shop.mapsUrl,
        shop.types == null ? List.of() : Arrays.asList(shop.types.split(",")),
        shop.photoUrls, shop.category);
  }
  public double distance(Double firstLatitude, Double firstLongitude,
      Double secondLatitude, Double secondLongitude) {
    if (firstLatitude == null || firstLongitude == null
        || secondLatitude == null || secondLongitude == null) return 0;
    double latitudeDelta = Math.toRadians(secondLatitude - firstLatitude);
    double longitudeDelta = Math.toRadians(secondLongitude - firstLongitude);
    double value = Math.sin(latitudeDelta / 2) * Math.sin(latitudeDelta / 2)
        + Math.cos(Math.toRadians(firstLatitude)) * Math.cos(Math.toRadians(secondLatitude))
        * Math.sin(longitudeDelta / 2) * Math.sin(longitudeDelta / 2);
    return Math.round(6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value)) * 10) / 10.0;
  }
}
