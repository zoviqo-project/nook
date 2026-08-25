package com.nook.infrastructure.adapter.out.auth;

import com.nook.application.port.out.OtpProviderPort;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import java.security.SecureRandom;
import java.util.concurrent.ConcurrentHashMap;

@Component
@Profile({"local","development","demo","test"})
public class DevelopmentOtpAdapter implements OtpProviderPort {
  private final SecureRandom random = new SecureRandom();
  private final ConcurrentHashMap<String,String> codes = new ConcurrentHashMap<>();
  @Override public OtpDelivery send(String phone) {
    String code=String.format("%06d",random.nextInt(1_000_000));
    String reference=java.util.UUID.randomUUID().toString();
    codes.put(reference,code);
    return new OtpDelivery(reference,code);
  }
  @Override public boolean verify(String providerReference,String phone,String code) {
    String expected=codes.get(providerReference);
    if(expected!=null&&expected.equals(code)){codes.remove(providerReference);return true;}
    return false;
  }
}
