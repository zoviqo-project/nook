CREATE TABLE intent_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(40) NOT NULL UNIQUE,
  name VARCHAR(80) NOT NULL,
  icon VARCHAR(80) NOT NULL,
  display_order SMALLINT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE intent_subcategories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES intent_categories(id),
  code VARCHAR(60) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  display_order SMALLINT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(category_id, display_order)
);

CREATE TABLE user_intents (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES intent_categories(id),
  subcategory_id UUID NOT NULL REFERENCES intent_subcategories(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_intent_subcategories_category ON intent_subcategories(category_id, display_order) WHERE active;
CREATE INDEX idx_user_intents_category ON user_intents(category_id, subcategory_id);

INSERT INTO intent_categories(code,name,icon,display_order) VALUES
 ('PROJECT','Proyecto','laptopcomputer',1),('MEET','Conocer','heart',2),
 ('TALK','Hablar','cup.and.saucer',3),('DO','Hacer algo','target',4),
 ('LEARN','Aprender','leaf',5),('HELP','Ayudar','hands.sparkles',6),
 ('SOCIAL','Social','globe.europe.africa',7);

INSERT INTO intent_subcategories(category_id,code,name,display_order)
SELECT c.id,v.code,v.name,v.ord FROM intent_categories c JOIN (VALUES
 ('PROJECT','WEB_PROJECT','Proyecto web',1),('PROJECT','MOBILE_APP','App móvil',2),('PROJECT','STARTUP','Startup',3),('PROJECT','BUSINESS','Negocio',4),('PROJECT','ECOMMERCE','Ecommerce',5),('PROJECT','ARTIFICIAL_INTELLIGENCE','Inteligencia artificial',6),('PROJECT','SOFTWARE_TECH','Software / tecnología',7),('PROJECT','DESIGN','Diseño',8),('PROJECT','PHOTOGRAPHY','Fotografía',9),('PROJECT','MUSIC','Música',10),('PROJECT','ART','Arte',11),('PROJECT','CONTENT_CREATION','Creación de contenido',12),('PROJECT','MARKETING','Marketing',13),('PROJECT','ENTREPRENEURSHIP','Emprendimiento',14),('PROJECT','FIND_PARTNER','Buscar socio/a',15),('PROJECT','PROFESSIONAL_NETWORKING','Networking profesional',16),('PROJECT','ONE_OFF_COLLABORATION','Colaboración puntual',17),('PROJECT','EXCHANGE_IDEAS','Intercambiar ideas',18),('PROJECT','OTHER_PROJECT','Otro proyecto',19),
 ('MEET','SERIOUS','Algo serio',1),('MEET','RELATIONSHIP','Relación',2),('MEET','NO_PRESSURE','Conocer sin presión',3),('MEET','SEE_WHAT_HAPPENS','Ver qué surge',4),('MEET','FRIENDSHIP','Amistad',5),('MEET','NEW_FRIENDSHIPS','Nuevas amistades',6),('MEET','NEW_PEOPLE','Gente nueva',7),('MEET','COMPANY','Compañía',8),('MEET','MAKE_PLANS','Hacer planes',9),('MEET','GO_FOR_DRINK','Salir a tomar algo',10),('MEET','SHARED_INTERESTS','Compartir aficiones',11),('MEET','LOCAL_PEOPLE','Conocer gente de mi zona',12),('MEET','NEW_IN_CITY','Conocer gente nueva en la ciudad',13),('MEET','TRAVEL_GETAWAYS','Viajar / hacer escapadas',14),('MEET','ACTIVITIES_TOGETHER','Actividades juntos',15),('MEET','SOCIAL_NETWORKING','Networking social',16),
 ('TALK','CHAT','Charlar',1),('TALK','HEAR_STORIES','Conocer historias',2),('TALK','NEED_TO_TALK','Necesito hablar',3),('TALK','VENT','Desahogarme',4),('TALK','HAVE_COMPANY','Tener compañía',5),('TALK','NOT_ALONE_NOW','No quiero estar solo/a ahora',6),('TALK','LISTEN_TO_SOMEONE','Escuchar a alguien',7),('TALK','BE_HEARD','Que alguien me escuche',8),('TALK','SHARE_DAY','Compartir cómo ha ido el día',9),('TALK','TALK_LIFE','Hablar de la vida',10),('TALK','DEEP_CONVERSATION','Conversación profunda',11),('TALK','CALM_CONVERSATION','Conversación tranquila',12),('TALK','ADVICE','Consejos',13),('TALK','SHARE_EXPERIENCES','Compartir experiencias',14),('TALK','TALK_WORK','Hablar de trabajo',15),('TALK','TALK_RELATIONSHIPS','Hablar de relaciones',16),('TALK','TALK_PROJECTS','Hablar de proyectos',17),('TALK','TALK_TRAVEL','Hablar de viajes',18),('TALK','PRACTICE_LANGUAGE','Practicar un idioma',19),('TALK','DEBATE_IDEAS','Debate / intercambio de ideas',20),
 ('DO','COFFEE','Tomar un café',1),('DO','WALK','Pasear',2),('DO','SPORT','Deporte',3),('DO','GYM','Gimnasio',4),('DO','RUNNING','Running',5),('DO','HIKING','Senderismo',6),('DO','CYCLING','Bicicleta',7),('DO','LUNCH','Ir a comer',8),('DO','DINNER','Ir a cenar',9),('DO','DRINKS','Ir de copas',10),('DO','CINEMA','Cine',11),('DO','THEATRE','Teatro',12),('DO','CONCERT','Concierto',13),('DO','EXHIBITION','Exposición',14),('DO','MUSEUM','Museo',15),('DO','PHOTOGRAPHY_ACTIVITY','Fotografía',16),('DO','VIDEO_GAMES','Videojuegos',17),('DO','BOARD_GAMES','Juegos de mesa',18),('DO','SHOPPING','Comprar',19),('DO','TRIP','Viaje',20),('DO','GETAWAY','Escapada',21),('DO','EVENT','Evento',22),('DO','STUDY','Estudiar',23),('DO','COWORKING','Coworking',24),
 ('LEARN','LANGUAGES','Idiomas',1),('LEARN','PROGRAMMING','Programación',2),('LEARN','AI','Inteligencia artificial',3),('LEARN','DESIGN_LEARNING','Diseño',4),('LEARN','MARKETING_LEARNING','Marketing',5),('LEARN','FINANCE','Finanzas',6),('LEARN','BUSINESS_LEARNING','Negocios',7),('LEARN','ENTREPRENEURSHIP_LEARNING','Emprendimiento',8),('LEARN','PHOTOGRAPHY_LEARNING','Fotografía',9),('LEARN','MUSIC_LEARNING','Música',10),('LEARN','ART_LEARNING','Arte',11),('LEARN','COOKING','Cocina',12),('LEARN','COFFEE_LEARNING','Café',13),('LEARN','CULTURE_LEARNING','Cultura',14),('LEARN','HISTORY','Historia',15),('LEARN','SCIENCE','Ciencia',16),('LEARN','KNOWLEDGE_EXCHANGE','Intercambio de conocimientos',17),('LEARN','INFORMAL_MENTORING','Mentoría informal',18),
 ('HELP','GIVE_ADVICE','Dar un consejo',1),('HELP','ASK_ADVICE','Pedir consejo',2),('HELP','PROFESSIONAL_HELP','Ayuda profesional',3),('HELP','CAREER_GUIDANCE','Orientación laboral',4),('HELP','REVIEW_IDEA','Revisar una idea',5),('HELP','REVIEW_PROJECT','Revisar un proyecto',6),('HELP','HELP_ENTREPRENEUR','Ayudar a emprender',7),('HELP','MENTORING','Mentoría',8),('HELP','SHARE_EXPERIENCE','Compartir experiencia',9),('HELP','CONTACTS','Contactos',10),('HELP','NETWORKING','Networking',11),('HELP','TECH_HELP','Ayuda tecnológica',12),('HELP','CREATIVE_HELP','Ayuda creativa',13),('HELP','INTERVIEW_PRACTICE','Practicar una entrevista',14),('HELP','PREPARE_PRESENTATION','Preparar una presentación',15),
 ('SOCIAL','NEIGHBORHOOD','Gente de mi barrio',1),('SOCIAL','CITY','Gente de mi ciudad',2),('SOCIAL','NEWCOMERS','Recién llegado/a',3),('SOCIAL','EXPATS','Expatriados',4),('SOCIAL','TRAVELERS','Viajeros',5),('SOCIAL','DIGITAL_NOMADS','Digital nomads',6),('SOCIAL','PROFESSIONALS','Profesionales',7),('SOCIAL','ENTREPRENEURS','Emprendedores',8),('SOCIAL','CREATIVES','Creativos',9),('SOCIAL','DEVELOPERS','Developers',10),('SOCIAL','ARTISTS','Artistas',11),('SOCIAL','MUSICIANS','Músicos',12),('SOCIAL','FOODIES','Foodies',13),('SOCIAL','COFFEE_LOVERS','Amantes del café',14),('SOCIAL','ANIMAL_LOVERS','Amantes de los animales',15),('SOCIAL','CULTURE','Cultura',16),('SOCIAL','TECHNOLOGY','Tecnología',17),('SOCIAL','SPORTS','Deporte',18)
) AS v(category_code,code,name,ord) ON c.code=v.category_code;

-- Existing users remain valid without an intention. Demo accounts receive varied safe defaults.
INSERT INTO user_intents(user_id,category_id,subcategory_id)
SELECT u.id,c.id,s.id FROM users u
JOIN intent_categories c ON c.code=CASE mod(abs(hashtext(u.email)::bigint),3) WHEN 0 THEN 'PROJECT' WHEN 1 THEN 'MEET' ELSE 'TALK' END
JOIN intent_subcategories s ON s.category_id=c.id AND s.display_order=1
WHERE lower(u.email) LIKE '%@nook.demo'
ON CONFLICT(user_id) DO NOTHING;
