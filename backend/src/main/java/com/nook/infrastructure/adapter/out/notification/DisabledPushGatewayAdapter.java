package com.nook.infrastructure.adapter.out.notification;

import com.nook.application.port.out.PushGatewayPort;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name="nook.apns.enabled",havingValue="false",matchIfMissing=true)
public class DisabledPushGatewayAdapter implements PushGatewayPort {
  @Override public void send(String deviceToken,String type,String title,String body,UUID resourceId) { }
}
