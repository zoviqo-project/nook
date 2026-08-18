package com.nook.controller;

import com.nook.dto.ApiDtos.MyCafeDto;
import com.nook.security.CurrentUser;
import com.nook.service.MyCafesService;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/my-cafes")
public class MyCafesController {
  private final MyCafesService service;
  public MyCafesController(MyCafesService service) { this.service = service; }
  @GetMapping public List<MyCafeDto> list() { return service.list(CurrentUser.id()); }
}
