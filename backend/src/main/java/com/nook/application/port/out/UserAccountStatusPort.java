package com.nook.application.port.out;

import java.util.UUID;

public interface UserAccountStatusPort {
  boolean isActive(UUID userId);
}
