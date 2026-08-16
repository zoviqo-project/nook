package com.nook.controller;

import com.nook.domain.SocialEntities.DateStatus;
import com.nook.dto.ApiDtos.CreateDate;
import com.nook.dto.ApiDtos.DateDto;
import com.nook.dto.ApiDtos.UpdateDate;
import com.nook.security.CurrentUser;
import com.nook.service.CoffeeDateService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/coffee-dates")
public class CoffeeDateController {
  private final CoffeeDateService service;
  public CoffeeDateController(CoffeeDateService service) { this.service = service; }

  @PostMapping @ResponseStatus(HttpStatus.CREATED)
  DateDto create(@Valid @RequestBody CreateDate request) { return service.create(CurrentUser.id(), request); }
  @GetMapping List<DateDto> list() { return service.list(CurrentUser.id()); }
  @GetMapping("/{id}") DateDto get(@PathVariable UUID id) {
    return service.list(CurrentUser.id()).stream().filter(d -> d.id().equals(id)).findFirst()
        .orElseThrow(() -> new org.springframework.web.server.ResponseStatusException(HttpStatus.NOT_FOUND));
  }
  @PatchMapping("/{id}") DateDto update(@PathVariable UUID id, @Valid @RequestBody UpdateDate request) { return service.update(CurrentUser.id(), id, request); }
  @PostMapping("/{id}/accept") DateDto accept(@PathVariable UUID id) { return service.transition(CurrentUser.id(), id, DateStatus.ACCEPTED); }
  @PostMapping("/{id}/decline") DateDto decline(@PathVariable UUID id) { return service.transition(CurrentUser.id(), id, DateStatus.DECLINED); }
  @PostMapping("/{id}/cancel") DateDto cancel(@PathVariable UUID id) { return service.transition(CurrentUser.id(), id, DateStatus.CANCELLED); }
  @PostMapping("/{id}/complete") DateDto complete(@PathVariable UUID id) { return service.complete(CurrentUser.id(), id); }
  @PostMapping("/{id}/counter") DateDto counter(@PathVariable UUID id, @Valid @RequestBody UpdateDate request) { return service.update(CurrentUser.id(), id, request); }
}
