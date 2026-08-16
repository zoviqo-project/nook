package com.nook.application.port.out;

public interface OtpProviderPort {
  void send(String phone, String code);
  boolean exposesDevelopmentCode();
}
