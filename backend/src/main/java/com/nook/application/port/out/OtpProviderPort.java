package com.nook.application.port.out;

public interface OtpProviderPort {
  OtpDelivery send(String phone);
  boolean verify(String providerReference, String phone, String code);
  record OtpDelivery(String providerReference, String developmentCode) {}
}
