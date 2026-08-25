package com.nook.infrastructure.adapter.out.auth;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.nook.application.port.out.OtpProviderPort;
import com.nook.exception.ApiException;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.client.*;

/** Uses Verify when available and real Twilio Messaging for restricted trial accounts. */
@Component @Profile("prod")
public class ProductionOtpAdapter implements OtpProviderPort {
  private final String accountSid,authToken,serviceSid,fromNumber;
  private final PasswordEncoder encoder;
  private static final Pattern TRIAL_CODE=Pattern.compile("(?<![0-9])[0-9]{6}(?![0-9])");
  private final RestClient verifyClient=RestClient.builder().baseUrl("https://verify.twilio.com/v2").build();
  private final RestClient messagingClient=RestClient.builder().baseUrl("https://api.twilio.com/2010-04-01").build();
  public ProductionOtpAdapter(@Value("${nook.sms.twilio-account-sid:}")String accountSid,
      @Value("${nook.sms.twilio-auth-token:}")String authToken,
      @Value("${nook.sms.twilio-verify-service-sid:}")String serviceSid,
      @Value("${nook.sms.twilio-from-number:}")String fromNumber,PasswordEncoder encoder){
    this.accountSid=accountSid.trim();this.authToken=authToken.trim();this.serviceSid=serviceSid.trim();
    this.fromNumber=fromNumber.trim();this.encoder=encoder;
  }
  @Override public OtpDelivery send(String phone){
    configured();
    if(!serviceSid.isBlank())return sendWithVerify(phone);
    var form=new LinkedMultiValueMap<String,String>();form.add("To",phone);form.add("From",fromNumber);
    // New Twilio trial accounts accept template identifiers rather than custom bodies.
    form.add("Body","sms_2fa");
    try{
      var value=messagingClient.post().uri("/Accounts/{sid}/Messages.json",accountSid)
          .headers(h->h.setBasicAuth(accountSid,authToken)).contentType(MediaType.APPLICATION_FORM_URLENCODED)
          .body(form).retrieve().body(TwilioResponse.class);
      var match=TRIAL_CODE.matcher(value==null||value.body()==null?"":value.body());
      if(!match.find())throw failure("SMS_TEMPLATE_INVALID","Twilio no ha devuelto un código OTP válido");
      String code=match.group();
      return new OtpDelivery(encoder.encode(code),null);
    }catch(RestClientResponseException e){throw providerError(e,"SMS_DELIVERY_FAILED","No hemos podido enviar el SMS");}
      catch(RuntimeException e){throw failure("SMS_PROVIDER_UNAVAILABLE","El servicio de SMS no responde");}
  }
  private OtpDelivery sendWithVerify(String phone){
    var form=new LinkedMultiValueMap<String,String>();form.add("To",phone);form.add("Channel","sms");
    try{
      var value=verifyClient.post().uri("/Services/{service}/Verifications",serviceSid)
          .headers(h->h.setBasicAuth(accountSid,authToken)).contentType(MediaType.APPLICATION_FORM_URLENCODED)
          .body(form).retrieve().body(TwilioResponse.class);
      if(value==null||value.sid()==null)throw failure("SMS_DELIVERY_FAILED","No hemos podido enviar el SMS");
      return new OtpDelivery(value.sid(),null);
    }catch(RestClientResponseException e){throw providerError(e,"SMS_DELIVERY_FAILED","No hemos podido enviar el SMS");}
  }
  @Override public boolean verify(String providerReference,String phone,String code){
    configured();
    if(serviceSid.isBlank())return providerReference!=null&&encoder.matches(code,providerReference);
    var form=new LinkedMultiValueMap<String,String>();form.add("To",phone);form.add("Code",code);
    try{
      var value=verifyClient.post().uri("/Services/{service}/VerificationCheck",serviceSid)
          .headers(h->h.setBasicAuth(accountSid,authToken)).contentType(MediaType.APPLICATION_FORM_URLENCODED)
          .body(form).retrieve().body(TwilioResponse.class);
      return value!=null&&"approved".equalsIgnoreCase(value.status());
    }catch(HttpClientErrorException.NotFound e){return false;}
      catch(RestClientResponseException e){throw providerError(e,"OTP_PROVIDER_ERROR","No hemos podido verificar el código");}
      catch(RuntimeException e){throw failure("SMS_PROVIDER_UNAVAILABLE","El servicio de SMS no responde");}
  }
  private void configured(){if(accountSid.isBlank()||authToken.isBlank()||(serviceSid.isBlank()&&fromNumber.isBlank()))
    throw failure("OTP_PROVIDER_UNAVAILABLE","El servicio de SMS no está configurado");}
  private ApiException providerError(RestClientResponseException e,String code,String message){
    return e.getStatusCode().value()==429?new ApiException(HttpStatus.TOO_MANY_REQUESTS,"OTP_RATE_LIMITED","Demasiados intentos. Espera antes de volver a intentarlo"):failure(code,message);
  }
  private ApiException failure(String code,String message){return new ApiException(HttpStatus.SERVICE_UNAVAILABLE,code,message);}
  @JsonIgnoreProperties(ignoreUnknown=true) private record TwilioResponse(String sid,String status,String body){}
}
