package com.nook;

import static org.mockito.Mockito.*;

import com.nook.application.port.out.PushGatewayPort;
import com.nook.domain.SocialEntities.*;
import com.nook.infrastructure.adapter.out.notification.DatabasePushNotificationAdapter;
import com.nook.repository.SocialRepository;
import java.util.*;
import org.junit.jupiter.api.Test;

class PushNotificationAdapterTest {
  @Test void persistsNotificationAndForwardsToEveryRegisteredDevice(){
    SocialRepository repository=mock(SocialRepository.class);PushGatewayPort gateway=mock(PushGatewayPort.class);
    UUID user=UUID.randomUUID(),resource=UUID.randomUUID();
    DeviceToken first=new DeviceToken();first.token="device-a";DeviceToken second=new DeviceToken();second.token="device-b";
    when(repository.deviceTokens(user)).thenReturn(List.of(first,second));

    new DatabasePushNotificationAdapter(repository,gateway).deliver(user,"MATCH","¡Tenemos café!","Laura también quiere quedar",resource);

    verify(repository).save(argThat(value->value instanceof Notification notification
        &&notification.userId.equals(user)&&notification.resourceId.equals(resource)));
    verify(gateway).send("device-a","MATCH","¡Tenemos café!","Laura también quiere quedar",resource);
    verify(gateway).send("device-b","MATCH","¡Tenemos café!","Laura también quiere quedar",resource);
  }
}
