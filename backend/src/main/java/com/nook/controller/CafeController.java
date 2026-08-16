package com.nook.controller;

import com.nook.dto.ApiDtos.ShopDto;
import com.nook.exception.ApiException;
import com.nook.service.CoffeeShopService;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/cafes")
public class CafeController {
  private final CoffeeShopService service;

  public CafeController(CoffeeShopService service) { this.service = service; }

  @GetMapping("/nearby")
  public List<ShopDto> nearby(
      @RequestParam double latitude,
      @RequestParam double longitude,
      @RequestParam(defaultValue = "2000") int radius) {
    if (!Double.isFinite(latitude) || latitude < -90 || latitude > 90
        || !Double.isFinite(longitude) || longitude < -180 || longitude > 180) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_COORDINATES", "Coordenadas no válidas");
    }
    if (radius < 500 || radius > 50_000) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_RADIUS", "El radio debe estar entre 500 y 50000 metros");
    }
    return service.nearby(latitude, longitude, radius / 1000.0);
  }
}
