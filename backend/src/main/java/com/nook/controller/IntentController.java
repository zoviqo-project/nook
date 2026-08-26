package com.nook.controller;

import com.nook.dto.ApiDtos.*;
import com.nook.security.CurrentUser;
import com.nook.service.IntentService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class IntentController {
  private final IntentService service;
  public IntentController(IntentService service) { this.service = service; }

  @GetMapping("/intent-categories")
  public List<IntentCategoryDto> categories() { return service.categories(); }

  @GetMapping("/users/me/intent")
  public UserIntentState current() { return service.current(CurrentUser.id()); }

  @PutMapping("/users/me/intent")
  public UserIntentState update(@Valid @RequestBody UpdateUserIntent request) {
    return service.update(CurrentUser.id(), request);
  }
}
