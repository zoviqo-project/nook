package com.nook;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.nook.domain.SocialEntities.*;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import com.nook.service.*;
import com.nook.application.port.out.PushNotificationPort;
import jakarta.persistence.EntityManager;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.*;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ConversationServiceTest {
  @Mock SocialRepository repository;
  @Mock SocialMapper mapper;
  @Mock EntityManager entityManager;
  @Mock PushNotificationPort push;

  private ConversationService service(){return new ConversationService(repository,mapper,entityManager,new AuditService(repository),push);}

  @Test void nonParticipantCannotSendMessage(){
    UUID user=UUID.randomUUID(),conversation=UUID.randomUUID();
    when(repository.conversationMember(conversation,user)).thenReturn(false);
    assertThatThrownBy(()->service().send(user,conversation,"hola",UUID.randomUUID()))
        .isInstanceOf(ApiException.class).hasMessageContaining("match activo");
  }

  @Test void repeatedClientMessageIdReturnsExistingMessageWithoutPersistingAgain(){
    UUID user=UUID.randomUUID(),conversation=UUID.randomUUID(),clientId=UUID.randomUUID();
    Message existing=new Message();existing.id=UUID.randomUUID();existing.senderId=user;existing.body="hola";existing.conversationId=conversation;
    when(repository.conversationMember(conversation,user)).thenReturn(true);
    when(repository.messageByClientId(conversation,clientId)).thenReturn(Optional.of(existing));
    var result=service().send(user,conversation,"hola",clientId);
    assertThat(result.id()).isEqualTo(existing.id);
    verify(repository,never()).save(any());
  }
}
