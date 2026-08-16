package com.nook.infrastructure.adapter.out.auth;

import com.nook.application.port.out.ExternalIdentityVerifier;
import com.nook.domain.SocialEntities.AuthProvider;
import com.nook.exception.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtDecoders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class OidcIdentityAdapter implements ExternalIdentityVerifier {
  private final String appleAudience;
  private final String googleAudience;
  private final String facebookAppId;
  private final String facebookAppSecret;
  private final RestClient http = RestClient.create("https://graph.facebook.com");
  private volatile JwtDecoder apple;
  private volatile JwtDecoder google;

  public OidcIdentityAdapter(
      @Value("${nook.auth.apple-client-id:}") String appleAudience,
      @Value("${nook.auth.google-client-id:}") String googleAudience,
      @Value("${nook.auth.facebook-app-id:}") String facebookAppId,
      @Value("${nook.auth.facebook-app-secret:}") String facebookAppSecret) {
    this.appleAudience = appleAudience;
    this.googleAudience = googleAudience;
    this.facebookAppId = facebookAppId;
    this.facebookAppSecret = facebookAppSecret;
  }

  @Override public VerifiedIdentity verify(AuthProvider provider, String token) {
    try {
      Jwt jwt = switch (provider) {
        case APPLE -> apple().decode(token);
        case GOOGLE -> google().decode(token);
        case FACEBOOK -> null;
        default -> throw new ApiException(HttpStatus.BAD_REQUEST, "UNSUPPORTED_PROVIDER", "Proveedor no compatible");
      };
      if (provider == AuthProvider.FACEBOOK) return verifyFacebook(token);
      String audience = provider == AuthProvider.APPLE ? appleAudience : googleAudience;
      if (audience.isBlank() || !jwt.getAudience().contains(audience)) {
        throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_IDENTITY_TOKEN", "La credencial no pertenece a Nook");
      }
      String email = jwt.getClaimAsString("email");
      Object verifiedClaim = jwt.getClaims().get("email_verified");
      boolean verified = Boolean.TRUE.equals(verifiedClaim) || "true".equalsIgnoreCase(String.valueOf(verifiedClaim));
      return new VerifiedIdentity(jwt.getSubject(), email, verified, jwt.getClaimAsString("name"));
    } catch (ApiException e) { throw e; }
    catch (Exception e) {
      throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_IDENTITY_TOKEN", "La credencial de acceso no es válida");
    }
  }

  private VerifiedIdentity verifyFacebook(String token) {
    if (facebookAppId.isBlank() || facebookAppSecret.isBlank())
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "PROVIDER_NOT_CONFIGURED", "Facebook Login no está configurado");
    FacebookDebug response = http.get().uri(uri -> uri.path("/debug_token")
        .queryParam("input_token", token).queryParam("access_token", facebookAppId + "|" + facebookAppSecret).build())
        .retrieve().body(FacebookDebug.class);
    if (response == null || response.data == null || !response.data.is_valid || !facebookAppId.equals(response.data.app_id))
      throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_IDENTITY_TOKEN", "La credencial de Facebook no es válida");
    FacebookMe me = http.get().uri(uri -> uri.path("/me").queryParam("fields", "id,name,email")
        .queryParam("access_token", token).build()).retrieve().body(FacebookMe.class);
    if (me == null || me.id == null) throw new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_IDENTITY_TOKEN", "La identidad de Facebook no es válida");
    return new VerifiedIdentity(me.id, me.email, me.email != null, me.name);
  }
  private record FacebookDebug(FacebookData data) {}
  private record FacebookData(boolean is_valid, String app_id, String user_id) {}
  private record FacebookMe(String id, String name, String email) {}

  private JwtDecoder apple() {
    if (apple == null) apple = JwtDecoders.fromIssuerLocation("https://appleid.apple.com");
    return apple;
  }
  private JwtDecoder google() {
    if (google == null) google = JwtDecoders.fromIssuerLocation("https://accounts.google.com");
    return google;
  }
}
