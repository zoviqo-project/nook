package com.nook.infrastructure.adapter.out.notification;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nimbusds.jose.*;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jwt.*;
import com.nook.application.port.out.PushGatewayPort;
import jakarta.annotation.PreDestroy;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.security.interfaces.ECPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.slf4j.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name="nook.apns.enabled",havingValue="true")
public class ApnsPushGatewayAdapter implements PushGatewayPort {
  private static final Logger log=LoggerFactory.getLogger(ApnsPushGatewayAdapter.class);
  private final String keyId,teamId,topic,host;
  private final ECPrivateKey privateKey;
  private final ObjectMapper mapper;
  private final HttpClient client=HttpClient.newBuilder().version(HttpClient.Version.HTTP_2).connectTimeout(Duration.ofSeconds(5)).build();
  private final ExecutorService executor=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"nook-apns");t.setDaemon(true);return t;});
  private volatile String cachedJwt;private volatile Instant jwtCreated=Instant.EPOCH;

  public ApnsPushGatewayAdapter(ObjectMapper mapper,@Value("${nook.apns.key-id}")String keyId,
      @Value("${nook.apns.team-id}")String teamId,@Value("${nook.apns.topic}")String topic,
      @Value("${nook.apns.private-key-path}")String keyPath,
      @Value("${nook.apns.sandbox:false}")boolean sandbox) {
    this.mapper=mapper;this.keyId=keyId;this.teamId=teamId;this.topic=topic;
    this.host=sandbox?"https://api.sandbox.push.apple.com":"https://api.push.apple.com";
    this.privateKey=loadKey(keyPath);
  }

  @Override public void send(String token,String type,String title,String body,UUID resourceId) {
    executor.execute(()->deliver(token,type,title,body,resourceId));
  }

  private void deliver(String token,String type,String title,String body,UUID resourceId) {
    try {
      Map<String,Object> alert=Map.of("title",title,"body",body);
      Map<String,Object> payload=new LinkedHashMap<>();payload.put("aps",Map.of("alert",alert,"sound","default"));payload.put("type",type);
      if(resourceId!=null)payload.put("resourceId",resourceId.toString());
      HttpRequest request=HttpRequest.newBuilder(URI.create(host+"/3/device/"+token))
          .timeout(Duration.ofSeconds(10)).header("authorization","bearer "+jwt())
          .header("apns-topic",topic).header("apns-push-type","alert").header("apns-priority","10")
          .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(payload),StandardCharsets.UTF_8)).build();
      HttpResponse<String> response=client.send(request,HttpResponse.BodyHandlers.ofString());
      if(response.statusCode()!=200)log.warn("APNs rejected notification status={}",response.statusCode());
    } catch(Exception error) { log.warn("APNs delivery failed: {}",error.getClass().getSimpleName()); }
  }

  private synchronized String jwt() throws JOSEException {
    if(cachedJwt!=null&&jwtCreated.isAfter(Instant.now().minusSeconds(3000)))return cachedJwt;
    jwtCreated=Instant.now();SignedJWT value=new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.ES256).keyID(keyId).build(),
        new JWTClaimsSet.Builder().issuer(teamId).issueTime(Date.from(jwtCreated)).build());
    value.sign(new ECDSASigner(privateKey));cachedJwt=value.serialize();return cachedJwt;
  }

  private ECPrivateKey loadKey(String path) {
    try {String pem=Files.readString(Path.of(path)).replace("-----BEGIN PRIVATE KEY-----","").replace("-----END PRIVATE KEY-----","").replaceAll("\\s","");
      byte[] encoded=Base64.getDecoder().decode(pem);return (ECPrivateKey)KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(encoded));
    } catch(Exception error){throw new IllegalStateException("No se pudo cargar la clave APNs",error);}
  }
  @PreDestroy void close(){executor.shutdown();}
}
