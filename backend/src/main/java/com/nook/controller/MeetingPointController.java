package com.nook.controller;

import com.nook.dto.ApiDtos.GeoPointDto;
import com.nook.security.CurrentUser;
import com.nook.service.MeetingPointService;
import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/matches")
public class MeetingPointController {
  private final MeetingPointService service;

  public MeetingPointController(MeetingPointService service) { this.service = service; }

  @GetMapping("/{id}/meeting-point")
  public GeoPointDto midpoint(@PathVariable UUID id) {
    return service.midpoint(id, CurrentUser.id());
  }
}
