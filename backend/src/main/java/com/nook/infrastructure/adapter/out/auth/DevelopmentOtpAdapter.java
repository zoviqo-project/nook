package com.nook.infrastructure.adapter.out.auth;

import com.nook.application.port.out.OtpProviderPort;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile({"local","development","demo","test"})
public class DevelopmentOtpAdapter implements OtpProviderPort {
  @Override public void send(String phone, String code) { /* Returned only by the restricted DEV response. */ }
  @Override public boolean exposesDevelopmentCode() { return true; }
}
