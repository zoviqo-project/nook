package com.nook;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import com.nook.application.port.out.MediaStoragePort;
import com.nook.domain.SocialEntities.Photo;
import com.nook.domain.SocialEntities.Preference;
import com.nook.domain.SocialEntities.Profile;
import com.nook.domain.SocialEntities.User;
import com.nook.dto.ApiDtos.UpdateMe;
import com.nook.exception.ApiException;
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

  @Test void onboardingProgressIsPersistedWithoutMovingBackwards(){
    UUID userId=UUID.randomUUID();User user=new User();user.id=userId;
    Profile profile=new Profile();profile.userId=userId;profile.name="Nuevo café";profile.onboardingStep=5;
    Preference preference=new Preference();preference.userId=userId;
    when(repository.user(userId)).thenReturn(user);when(repository.profile(userId)).thenReturn(profile);
    when(repository.preference(userId)).thenReturn(preference);
    var service=new UserService(repository,mapper,new AuditService(repository),media);

    service.update(userId,update(3,false));
    assertThat(profile.onboardingStep).isEqualTo(5);
    service.update(userId,update(8,false));
    assertThat(profile.onboardingStep).isEqualTo(8);
  }

  @Test void incompleteProfileCannotBePublished(){
    UUID userId=UUID.randomUUID();User user=new User();user.id=userId;
    Profile profile=new Profile();profile.userId=userId;profile.name="Nuevo café";
    Preference preference=new Preference();preference.userId=userId;
    when(repository.user(userId)).thenReturn(user);when(repository.profile(userId)).thenReturn(profile);
    when(repository.preference(userId)).thenReturn(preference);

    org.assertj.core.api.Assertions.assertThatThrownBy(()->
        new UserService(repository,mapper,new AuditService(repository),media)
            .update(userId,update(15,true))).isInstanceOf(ApiException.class);
  }

  private UpdateMe update(Integer step,Boolean complete){
    return new UpdateMe(
        null,null,null,null,null,null,null,null,null,null,null,null,null,
        null,null,null,null,null,null,complete,step,null,null,null,null,null);
  }
}
