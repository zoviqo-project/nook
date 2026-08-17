package com.nook.controller;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.context.annotation.Profile;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.client.RestClient;

@Controller
@Profile({"demo", "demo-data", "staging"})
@RequestMapping("/api/v1/demo/photos")
public class DemoPhotoController {
  private static final String[] SOURCES = {
    "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=1000&q=85",
    "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=1000&q=85",
    "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=1000&q=85",
    "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=1000&q=85"
  };
  private final ConcurrentHashMap<Integer, byte[]> cache = new ConcurrentHashMap<>();
  private final RestClient client;

  public DemoPhotoController() {
    var factory = new org.springframework.http.client.SimpleClientHttpRequestFactory();
    factory.setConnectTimeout(Duration.ofSeconds(4));
    factory.setReadTimeout(Duration.ofSeconds(12));
    client = RestClient.builder().requestFactory(factory).build();
  }

  @GetMapping("/{index}")
  ResponseEntity<byte[]> photo(@PathVariable int index) {
    if (index < 0 || index >= SOURCES.length) return ResponseEntity.notFound().build();
    byte[] bytes = cache.computeIfAbsent(index, key -> client.get().uri(SOURCES[key]).retrieve().body(byte[].class));
    if (bytes == null || bytes.length == 0) return ResponseEntity.notFound().build();
    return ResponseEntity.ok()
      .cacheControl(CacheControl.maxAge(Duration.ofDays(7)).cachePublic())
      .contentType(MediaType.IMAGE_JPEG)
      .body(bytes);
  }
}
