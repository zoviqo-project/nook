package com.nook.service;

import com.nook.domain.SocialEntities.*;
import com.nook.dto.ApiDtos.*;
import com.nook.exception.ApiException;
import com.nook.repository.SocialRepository;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class NotificationService {
  private final SocialRepository repository;
  public NotificationService(SocialRepository repository) { this.repository=repository; }
  public PageDto<NotificationDto> list(UUID user,int page,int size) {
    var values=repository.notifications(user,page,size+1);
    return new PageDto<>(values.stream().limit(size).map(n->new NotificationDto(n.id,n.type,n.title,n.body,n.resourceId,n.createdAt,n.readAt!=null)).toList(),page,size,values.size()>size);
  }
  @Transactional public void read(UUID user,UUID id) {
    Notification n=repository.find(Notification.class,id);
    if(n==null||!n.userId.equals(user))throw new ApiException(HttpStatus.NOT_FOUND,"NOTIFICATION_NOT_FOUND","Notificación no encontrada");
    n.readAt=Instant.now();
  }
  @Transactional public void registerDevice(UUID user,String token) {
    DeviceToken device=repository.deviceToken(token).orElseGet(DeviceToken::new);
    device.userId=user;device.token=token;device.platform="IOS";device.updatedAt=Instant.now();repository.save(device);
  }
  @Transactional public void removeDevice(UUID user,String token) {
    repository.deviceToken(token).filter(d->d.userId.equals(user)).ifPresent(repository::remove);
  }
}
