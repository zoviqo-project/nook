package com.nook.infrastructure.adapter.out.auth;

import com.nook.application.port.out.OtpProviderPort;
import com.nook.exception.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.MediaType;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

@Component
@Profile("prod")
public class ProductionOtpAdapter implements OtpProviderPort {
  private final String accountSid;
  private final String authToken;
  private final String fromNumber;
  private final String messagingServiceSid;
  private final RestClient client;

  public ProductionOtpAdapter(
      @Value("${nook.sms.twilio-account-sid:}") String accountSid,
      @Value("${nook.sms.twilio-auth-token:}") String authToken,
      @Value("${nook.sms.twilio-from-number:}") String fromNumber,
      @Value("${nook.sms.twilio-messaging-service-sid:}") String messagingServiceSid) {
    this.accountSid = accountSid.trim();
    this.authToken = authToken.trim();
    this.fromNumber = fromNumber.trim();
    this.messagingServiceSid = messagingServiceSid.trim();
    this.client = RestClient.builder().baseUrl("https://api.twilio.com/2010-04-01").build();
  }

  @Override public void send(String phone, String code) {
    if(accountSid.isBlank() || authToken.isBlank() || (fromNumber.isBlank() && messagingServiceSid.isBlank())) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OTP_PROVIDER_UNAVAILABLE", "El servicio de SMS no está configurado");
    }
    var form = new LinkedMultiValueMap<String,String>();
    form.add("To", phone);
    if(!messagingServiceSid.isBlank()) form.add("MessagingServiceSid", messagingServiceSid);
    else form.add("From", fromNumber);
    form.add("Body", "Tu código de Nook es " + code + ". Caduca en 5 minutos. No lo compartas.");
    try {
      client.post()
          .uri("/Accounts/{sid}/Messages.json", accountSid)
          .headers(headers -> headers.setBasicAuth(accountSid, authToken))
          .contentType(MediaType.APPLICATION_FORM_URLENCODED)
          .body(form)
          .retrieve()
          .toBodilessEntity();
    } catch(RestClientResponseException exception) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "SMS_DELIVERY_FAILED", "No hemos podido enviar el SMS");
    } catch(RuntimeException exception) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "SMS_PROVIDER_UNAVAILABLE", "El servicio de SMS no responde");
    }
  }
  @Override public boolean exposesDevelopmentCode() { return false; }
}
