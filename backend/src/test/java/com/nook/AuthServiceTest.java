package com.nook;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.nook.application.port.out.*;
import com.nook.domain.SocialEntities.*;
import com.nook.dto.ApiDtos.*;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import com.nook.security.JwtService;
import com.nook.service.*;
import jakarta.persistence.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.*;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {
  @Mock SocialRepository repository;
  @Mock PasswordEncoder encoder;
  @Mock JwtService jwt;
  @Mock SocialMapper mapper;
  @Mock EntityManager entityManager;
  @Mock ExternalIdentityVerifier identities;
  @Mock OtpProviderPort otp;
  @Mock AuditService audit;

  private AuthService service(){return new AuthService(repository,encoder,jwt,mapper,entityManager,30,identities,otp,audit);}

  @Test void emailRegistrationCreatesOnlyCredentialsAndAProvisionalProfile(){
    when(repository.userByEmail("new@nook.app")).thenReturn(Optional.empty());
    when(encoder.encode(anyString())).thenReturn("hash");
    doAnswer(invocation->{Object value=invocation.getArgument(0);if(value instanceof User user)user.id=UUID.randomUUID();return value;})
        .when(repository).save(any());

    service().register(new Register(" NEW@NOOK.APP ","coffee123"));

    verify(repository).save(argThat(value->value instanceof User user
        && user.email.equals("new@nook.app")&&user.passwordHash.equals("hash")));
    verify(repository).save(argThat(value->value instanceof Profile profile
        && profile.name.equals("Nuevo café")&&!profile.onboardingComplete));
    verify(repository).save(argThat(value->value instanceof AuthIdentity identity
        && identity.provider==AuthProvider.EMAIL&&identity.providerSubject.equals("new@nook.app")));
  }

  @Test void repeatedEmailRegistrationNeverCreatesADuplicate(){
    when(repository.userByEmail("member@nook.app")).thenReturn(Optional.of(new User()));

    assertThatThrownBy(()->service().register(new Register("member@nook.app","coffee123")))
        .isInstanceOf(com.nook.exception.ApiException.class);

    verify(repository,never()).save(any());
  }

  @Test void federatedLoginTrustsVerifiedProviderSubjectNotClientProfile(){
    UUID userId=UUID.randomUUID();
    User user=new User();user.id=userId;user.email="verified@nook.app";
    AuthIdentity identity=new AuthIdentity();identity.userId=userId;identity.provider=AuthProvider.GOOGLE;identity.providerSubject="google-sub";
    when(identities.verify(AuthProvider.GOOGLE,"signed-token")).thenReturn(
        new ExternalIdentityVerifier.VerifiedIdentity("google-sub","verified@nook.app",true,"Laura",
            "https://lh3.googleusercontent.com/avatar"));
    when(repository.identity(AuthProvider.GOOGLE,"google-sub")).thenReturn(Optional.of(identity));
    when(repository.user(userId)).thenReturn(user);
    when(jwt.issue(userId)).thenReturn("access");when(jwt.expiresSeconds()).thenReturn(1800L);

    Token token=service().federated(AuthProvider.GOOGLE,new FederatedAuth("signed-token","Untrusted name"));

    assertThat(token.accessToken()).isEqualTo("access");
    verify(identities).verify(AuthProvider.GOOGLE,"signed-token");
    verify(repository).lockAuthIdentityKey(AuthProvider.GOOGLE,"google-sub");
    verify(repository).save(argThat(value -> value instanceof Photo photo
        && photo.source.equals("SOCIAL") && photo.provider.equals("GOOGLE")
        && photo.url.equals("https://lh3.googleusercontent.com/avatar")));
    verify(audit).record(userId,"LOGIN","USER",userId);
  }

  @Test void phoneOtpIsRandomSixDigitsAndOnlyExposedByDevelopmentAdapter(){
    when(otp.exposesDevelopmentCode()).thenReturn(true);
    when(encoder.encode(anyString())).thenReturn("otp-hash");
    PhoneOtpRequested result=service().requestPhoneOtp("+34600000000");
    assertThat(result.developmentCode()).matches("[0-9]{6}");
    verify(otp).send(eq("+34600000000"),matches("[0-9]{6}"));
  }

  @Test void phoneOtpCannotBeResentBeforeCooldownExpires(){
    PhoneOtpChallenge recent=new PhoneOtpChallenge();recent.createdAt=Instant.now();
    when(repository.latestOtp("+34600000000")).thenReturn(Optional.of(recent));

    assertThatThrownBy(()->service().requestPhoneOtp("+34600000000"))
        .isInstanceOf(com.nook.exception.ApiException.class)
        .hasMessageContaining("30 segundos");
    verify(otp,never()).send(anyString(),anyString());
  }

  @Test void unverifiedFederatedEmailIsNeverLinkedToAnExistingAccount(){
    when(identities.verify(AuthProvider.GOOGLE,"signed-token")).thenReturn(
        new ExternalIdentityVerifier.VerifiedIdentity("attacker-sub","victim@nook.app",false,"Coffee",null));
    when(repository.identity(AuthProvider.GOOGLE,"attacker-sub")).thenReturn(Optional.empty());
    when(encoder.encode(anyString())).thenReturn("hash");
    when(jwt.issue(any())).thenReturn("access");

    service().federated(AuthProvider.GOOGLE,new FederatedAuth("signed-token",null));

    verify(repository,never()).userByEmail("victim@nook.app");
    verify(repository).save(argThat(value -> value instanceof User user
        && user.email.endsWith("@identity.nook.invalid")));
  }

  @Test void validPhoneOtpIsConsumedAndCannotBeReused(){
    UUID challengeId=UUID.randomUUID(),userId=UUID.randomUUID();String code="483921",phone="+34600000000";
    PhoneOtpChallenge challenge=new PhoneOtpChallenge();challenge.id=challengeId;challenge.phone=phone;
    challenge.codeHash="otp-hash";challenge.expiresAt=Instant.now().plusSeconds(120);
    AuthIdentity identity=new AuthIdentity();identity.userId=userId;identity.provider=AuthProvider.PHONE;identity.providerSubject=phone;
    User user=new User();user.id=userId;
    when(repository.otp(challengeId)).thenReturn(Optional.of(challenge));
    when(repository.identity(AuthProvider.PHONE,phone)).thenReturn(Optional.of(identity));
    when(repository.user(userId)).thenReturn(user);
    when(encoder.matches(code,"otp-hash")).thenReturn(true);
    when(jwt.issue(userId)).thenReturn("access");when(jwt.expiresSeconds()).thenReturn(1800L);

    service().verifyPhoneOtp(new PhoneOtpVerify(challengeId,code));

    assertThat(challenge.consumedAt).isNotNull();assertThat(challenge.attempts).isEqualTo((short)1);
    assertThatThrownBy(()->service().verifyPhoneOtp(new PhoneOtpVerify(challengeId,code)))
        .hasMessageContaining("caducado");
  }

  @Test void refreshRevokesUsedTokenBeforeIssuingRotatedSession(){
    String raw="old-refresh";UUID userId=UUID.randomUUID();
    RefreshToken stored=new RefreshToken();stored.userId=userId;stored.expiresAt=Instant.now().plusSeconds(300);
    User user=new User();user.id=userId;
    @SuppressWarnings("unchecked") TypedQuery<RefreshToken> query=mock(TypedQuery.class);
    when(entityManager.createQuery(anyString(),eq(RefreshToken.class))).thenReturn(query);
    when(query.setParameter(anyString(),any())).thenReturn(query);
    when(query.setLockMode(any())).thenReturn(query);
    when(query.getResultStream()).thenReturn(java.util.stream.Stream.of(stored));
    when(repository.user(userId)).thenReturn(user);when(jwt.issue(userId)).thenReturn("new-access");

    Token rotated=service().refresh(raw);

    assertThat(stored.revokedAt).isNotNull();assertThat(rotated.refreshToken()).isNotEqualTo(raw);
    verify(repository).save(argThat(value->value instanceof RefreshToken token&&token.userId.equals(userId)));
  }

  private String sha256(String value){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));}catch(Exception error){throw new AssertionError(error);}}
}
