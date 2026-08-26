package com.nook;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.nook.domain.SocialEntities.*;
import com.nook.exception.ApiException;
import com.nook.mapper.SocialMapper;
import com.nook.repository.SocialRepository;
import com.nook.service.*;
import com.nook.application.port.out.PushNotificationPort;
import com.nook.dto.ApiDtos.DiscoverProfile;
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

  @Test void conversationListUsesTheSameWorkingMessageQueryAsChatHistory(){
    UUID user=UUID.randomUUID(),other=UUID.randomUUID();
    Conversation conversation=new Conversation();conversation.id=UUID.randomUUID();conversation.matchId=UUID.randomUUID();
    Match match=new Match();match.id=conversation.matchId;match.userOneId=user;match.userTwoId=other;
    Profile profile=new Profile();profile.userId=other;
    Message latest=new Message();latest.body="Último mensaje";
    DiscoverProfile person=new DiscoverProfile(other,"Laura",29,"Bio","Barcelona",1.0,
        null,null,null,null,null,LookingFor.CASUAL_COFFEE,List.of(),List.of(),null);
    when(repository.conversations(user)).thenReturn(List.of(conversation));
    when(repository.find(Match.class,conversation.matchId)).thenReturn(match);
    when(repository.profile(other)).thenReturn(profile);
    when(repository.messages(conversation.id,0,1)).thenReturn(List.of(latest));
    when(mapper.profile(user,profile)).thenReturn(person);

    var result=service().list(user);

    assertThat(result).hasSize(1);
    assertThat(result.get(0).lastMessage()).isEqualTo("Último mensaje");
    verifyNoInteractions(entityManager);
  }
}
