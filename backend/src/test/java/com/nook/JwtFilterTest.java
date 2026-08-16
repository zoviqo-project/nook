package com.nook;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

import com.nook.application.port.out.UserAccountStatusPort;
import com.nook.security.*;
import jakarta.servlet.FilterChain;
import java.util.UUID;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.*;
import org.springframework.security.core.context.SecurityContextHolder;

class JwtFilterTest {
  @AfterEach void clear(){SecurityContextHolder.clearContext();}

  @Test void validTokenForDisabledUserDoesNotAuthenticate() throws Exception {
    JwtService jwt=mock(JwtService.class);UserAccountStatusPort users=mock(UserAccountStatusPort.class);
    UUID id=UUID.randomUUID();when(jwt.parse("token")).thenReturn(id);when(users.isActive(id)).thenReturn(false);
    var request=new MockHttpServletRequest();request.addHeader("Authorization","Bearer token");
    new JwtFilter(jwt,users).doFilter(request,new MockHttpServletResponse(),mock(FilterChain.class));
    assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
  }

  @Test void validTokenForActiveUserAuthenticates() throws Exception {
    JwtService jwt=mock(JwtService.class);UserAccountStatusPort users=mock(UserAccountStatusPort.class);
    UUID id=UUID.randomUUID();when(jwt.parse("token")).thenReturn(id);when(users.isActive(id)).thenReturn(true);
    var request=new MockHttpServletRequest();request.addHeader("Authorization","Bearer token");
    new JwtFilter(jwt,users).doFilter(request,new MockHttpServletResponse(),mock(FilterChain.class));
    assertThat(SecurityContextHolder.getContext().getAuthentication().getPrincipal()).isEqualTo(id);
  }
}
