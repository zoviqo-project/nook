package com.nook.controller;

import com.nook.application.port.out.MediaStoragePort;
import com.nook.dto.ApiDtos.*;
import com.nook.security.CurrentUser;
import com.nook.service.UserService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1")
public class UserController {
  private final UserService service;
  public UserController(UserService service) { this.service = service; }

  @GetMapping("/users/me") Me me() { return service.me(CurrentUser.id()); }
  @GetMapping("/users/me/settings") UserSettingsDto settings() { return service.settings(CurrentUser.id()); }
  @PutMapping("/users/me/settings") UserSettingsDto updateSettings(@Valid @RequestBody UpdateUserSettings value) { return service.updateSettings(CurrentUser.id(), value); }
  @PutMapping("/users/me/location") @ResponseStatus(HttpStatus.NO_CONTENT)
  void updateLocation(@Valid @RequestBody UpdateUserLocation value) { service.updateLocation(CurrentUser.id(), value); }
  @GetMapping("/users/{id}") DiscoverProfile profile(@PathVariable UUID id) { return service.profile(CurrentUser.id(), id); }
  @PatchMapping("/users/me") Me update(@Valid @RequestBody UpdateMe value) { return service.update(CurrentUser.id(), value); }

  @PostMapping(value="/users/me/photos", consumes=MediaType.MULTIPART_FORM_DATA_VALUE)
  @ResponseStatus(HttpStatus.CREATED)
  PhotoDto photoUpload(@RequestPart("file") MultipartFile file) { return service.uploadPhoto(CurrentUser.id(), file); }
  @PatchMapping("/users/me/photos/reorder")
  List<PhotoDto> reorder(@Valid @RequestBody PhotoOrder value) { return service.reorderPhotos(CurrentUser.id(), value.photoIds()); }
  @PatchMapping("/users/me/photos/{id}/primary")
  PhotoDto primary(@PathVariable UUID id) { return service.makePrimary(CurrentUser.id(), id); }
  @DeleteMapping("/users/me/photos/{id}") @ResponseStatus(HttpStatus.NO_CONTENT)
  void photoDelete(@PathVariable UUID id) { service.removePhoto(CurrentUser.id(), id); }

  @GetMapping("/media/photos/{filename:.+}")
  ResponseEntity<byte[]> photoFile(@PathVariable String filename) {
    MediaStoragePort.StoredContent content = service.photoContent(filename);
    MediaType type;
    try { type = MediaType.parseMediaType(content.contentType()); }
    catch (IllegalArgumentException ignored) { type = MediaType.IMAGE_JPEG; }
    return ResponseEntity.ok().cacheControl(CacheControl.maxAge(java.time.Duration.ofDays(1)).cachePublic())
        .contentType(type).body(content.bytes());
  }

  @PostMapping("/users/{id}/block") @ResponseStatus(HttpStatus.NO_CONTENT)
  void block(@PathVariable UUID id) { service.block(CurrentUser.id(), id); }
  @PostMapping("/users/{id}/report") @ResponseStatus(HttpStatus.NO_CONTENT)
  void report(@PathVariable UUID id, @Valid @RequestBody ReportRequest value) { service.report(CurrentUser.id(), id, value); }
  @DeleteMapping("/users/me") @ResponseStatus(HttpStatus.NO_CONTENT)
  void delete() { service.deleteAccount(CurrentUser.id()); }
}
