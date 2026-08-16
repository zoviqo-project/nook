package com.nook.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nook.dto.ApiDtos.ErrorDto;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.time.Instant;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

@Component
public class ApiAuthenticationEntryPoint implements AuthenticationEntryPoint {
  private final ObjectMapper mapper;
  public ApiAuthenticationEntryPoint(ObjectMapper mapper){this.mapper=mapper;}
  @Override public void commence(HttpServletRequest request,HttpServletResponse response,AuthenticationException exception)throws IOException{
    response.setStatus(401);response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    mapper.writeValue(response.getOutputStream(),new ErrorDto(Instant.now(),401,"UNAUTHORIZED","Necesitas iniciar sesión",request.getRequestURI(),Map.of()));
  }
}
