package com.nook.application.port.out;

import java.util.UUID;

public interface PushNotificationPort {
  void deliver(UUID userId, String type, String title, String body, UUID resourceId);
}
