package com.nook.service;

import com.nook.domain.SocialEntities.AuditEvent;
import com.nook.repository.SocialRepository;
import java.util.UUID;
import org.springframework.stereotype.Service;

@Service
public class AuditService {
  private final SocialRepository repository;
  public AuditService(SocialRepository repository){this.repository=repository;}
  public void record(UUID actor,String event,String resourceType,UUID resourceId){AuditEvent value=new AuditEvent();value.actorUserId=actor;value.eventType=event;value.resourceType=resourceType;value.resourceId=resourceId;repository.save(value);}
}
