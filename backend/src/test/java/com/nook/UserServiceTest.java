package com.nook;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import com.nook.application.port.out.MediaStoragePort;
import com.nook.domain.SocialEntities.Photo;
import com.nook.domain.SocialEntities.User;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import com.nook.service.AuditService;
import com.nook.service.UserService;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;

@ExtendWith(MockitoExtension.class)
class UserServiceTest {
  @Mock SocialRepository repository;
  @Mock SocialMapper mapper;
  @Mock MediaStoragePort media;

  @Test
  void firstManualPhotoImmediatelyBecomesPrimaryEvenWhenSocialPhotoExists() {
    UUID userId = UUID.randomUUID();
    User user = new User();
    user.id = userId;
    Photo social = new Photo();
    social.userId = userId;
    social.source = "SOCIAL";
    social.primary = true;
    when(repository.user(userId)).thenReturn(user);
    when(repository.userPhotos(userId)).thenReturn(List.of());
    when(media.storeUserPhoto(any(), any(), eq("image/jpeg")))
        .thenReturn(new MediaStoragePort.StoredMedia("/api/v1/media/photos/manual.jpg", "manual.jpg"));
    var file = new MockMultipartFile("file", "portrait.jpg", "image/jpeg", new byte[] {1, 2, 3});

    new UserService(repository, mapper, new AuditService(repository), media).uploadPhoto(userId, file);

    ArgumentCaptor<Photo> saved = ArgumentCaptor.forClass(Photo.class);
    verify(repository).save(saved.capture());
    assertThat(saved.getValue().source).isEqualTo("USER");
    assertThat(saved.getValue().primary).isTrue();
    assertThat(saved.getValue().position).isZero();
    verify(repository, never()).photos(userId);
  }

  @Test
  void additionalManualPhotoDoesNotReplaceExistingManualPrimary() {
    UUID userId = UUID.randomUUID();
    User user = new User();
    user.id = userId;
    Photo existing = new Photo();
    existing.userId = userId;
    existing.source = "USER";
    existing.primary = true;
    when(repository.user(userId)).thenReturn(user);
    when(repository.userPhotos(userId)).thenReturn(List.of(existing));
    when(media.storeUserPhoto(any(), any(), eq("image/png")))
        .thenReturn(new MediaStoragePort.StoredMedia("/api/v1/media/photos/second.png", "second.png"));
    var file = new MockMultipartFile("file", "second.png", "image/png", new byte[] {1, 2, 3});

    new UserService(repository, mapper, new AuditService(repository), media).uploadPhoto(userId, file);

    ArgumentCaptor<Photo> saved = ArgumentCaptor.forClass(Photo.class);
    verify(repository).save(saved.capture());
    assertThat(saved.getValue().primary).isFalse();
    assertThat(saved.getValue().position).isEqualTo(1);
  }
}
