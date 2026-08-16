package com.nook.application.port.out;

import java.util.UUID;

public interface PushGatewayPort {
  void send(String deviceToken,String type,String title,String body,UUID resourceId);
}
