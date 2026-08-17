package com.nook.controller;

import com.nook.application.port.out.PlacePhotoPort;
import com.nook.dto.ApiDtos.ShopDto;
import com.nook.service.CoffeeShopService;
import java.time.Duration;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/coffee-shops")
public class CoffeeShopController {
  private final CoffeeShopService service;
  private final PlacePhotoPort photos;

  public CoffeeShopController(CoffeeShopService service, PlacePhotoPort photos) {
    this.service = service;
    this.photos = photos;
  }

  @GetMapping("/photos/{token}")
  ResponseEntity<byte[]> photo(@PathVariable String token) {
    PlacePhotoPort.PhotoAsset photo = photos.photo(token);
    MediaType contentType;
    try { contentType = MediaType.parseMediaType(photo.contentType()); }
    catch (IllegalArgumentException ignored) { contentType = MediaType.IMAGE_JPEG; }
    return ResponseEntity.ok()
        .cacheControl(CacheControl.maxAge(Duration.ofDays(1)).cachePublic())
        .contentType(contentType)
        .body(photo.bytes());
  }

  @GetMapping("/{id}")
  ShopDto one(
      @PathVariable UUID id, @RequestParam double latitude, @RequestParam double longitude) {
    return service.one(id, latitude, longitude);
  }
}
