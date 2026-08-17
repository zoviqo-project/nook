package com.nook.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nook.dto.ApiDtos.ErrorDto;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.time.*;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class RateLimitFilter extends OncePerRequestFilter {
  private final ObjectMapper mapper;
  private final ConcurrentHashMap<String,Window> windows=new ConcurrentHashMap<>();
  public RateLimitFilter(ObjectMapper mapper){this.mapper=mapper;}
  @Override protected void doFilterInternal(HttpServletRequest req,HttpServletResponse res,FilterChain chain)throws ServletException,IOException{
    Rule rule=rule(req);
    if(rule==null){chain.doFilter(req,res);return;}
    String forwarded=req.getHeader("X-Forwarded-For");
    String client=forwarded==null?req.getRemoteAddr():forwarded.split(",",2)[0].trim();
    String key=client+":"+rule.group;
    long minute=Instant.now().getEpochSecond()/60;
    Window window=windows.compute(key,(ignored,current)->current==null||current.minute!=minute?new Window(minute,1):new Window(minute,current.count+1));
    if(window.count>rule.limit){res.setStatus(429);res.setContentType(MediaType.APPLICATION_JSON_VALUE);res.setHeader("Retry-After","60");mapper.writeValue(res.getOutputStream(),new ErrorDto(Instant.now(),429,"RATE_LIMITED","Demasiadas solicitudes. Espera un momento.",req.getRequestURI(),Map.of()));return;}
    if(windows.size()>10_000)windows.entrySet().removeIf(e->e.getValue().minute<minute-2);
    chain.doFilter(req,res);
  }
  private Rule rule(HttpServletRequest request){String path=request.getRequestURI();if(path.contains("/auth/phone/"))return new Rule("otp",8);if(path.contains("/auth/"))return new Rule("auth",20);if(path.contains("/coffee-likes/"))return new Rule("likes",60);if(path.contains("/messages"))return new Rule("messages",120);if(path.contains("/cafes/nearby"))return new Rule("places",30);return null;}
  private record Rule(String group,int limit){} private record Window(long minute,int count){}
}
