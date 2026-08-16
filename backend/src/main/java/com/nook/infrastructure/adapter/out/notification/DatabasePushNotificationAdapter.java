package com.nook.infrastructure.adapter.out.notification;

import com.nook.application.port.out.PushNotificationPort;
import com.nook.application.port.out.PushGatewayPort;
import com.nook.domain.SocialEntities.Notification;
import com.nook.repository.SocialRepository;
import java.util.UUID;
import org.springframework.stereotype.Component;

@Component
public class DatabasePushNotificationAdapter implements PushNotificationPort {
  private final SocialRepository repository;
  private final PushGatewayPort gateway;
  public DatabasePushNotificationAdapter(SocialRepository repository,PushGatewayPort gateway) { this.repository = repository;this.gateway=gateway; }
  @Override public void deliver(UUID userId,String type,String title,String body,UUID resourceId) {
    Notification n=new Notification();n.userId=userId;n.type=type;n.title=title;n.body=body;n.resourceId=resourceId;repository.save(n);
    repository.deviceTokens(userId).forEach(device->gateway.send(device.token,type,title,body,resourceId));
  }
}
