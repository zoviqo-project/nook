package com.nook.infrastructure.adapter.out.auth;

import com.nook.application.port.out.OtpProviderPort;
import com.nook.exception.ApiException;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
@Profile("prod")
public class ProductionOtpAdapter implements OtpProviderPort {
  @Override public void send(String phone, String code) {
    throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OTP_PROVIDER_UNAVAILABLE", "El envío de SMS no está configurado");
  }
  @Override public boolean exposesDevelopmentCode() { return false; }
}
