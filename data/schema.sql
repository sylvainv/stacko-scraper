BEGIN;

CREATE SCHEMA IF NOT EXISTS internal;
CREATE SCHEMA IF NOT EXISTS api;

GRANT USAGE ON SCHEMA api TO manati_user;
REVOKE USAGE on SCHEMA internal FROM manati_user;

CREATE OR REPLACE VIEW api.users AS
  SELECT app_id::int as id, '*******'::text as password, data->>'username' as usernname FROM manati_auth.users;


DROP TRIGGER if exists create_stacko_user on internal.users;
CREATE TRIGGER create_stacko_user BEFORE INSERT ON internal.users FOR EACH ROW EXECUTE PROCEDURE internal.create_user();

CREATE TABLE IF NOT EXISTS internal.posts (
  id SERIAL PRIMARY KEY,
  content TEXT NOT NULL,
  vote SMALLINT NOT NULL DEFAULT 0,
  user_id UUID NOT NULL REFERENCES manati_auth.users(id)
);
SELECT manati_utils.create_timestamps('internal.posts');
CREATE INDEX posts_user_id_idx ON internal.posts(user_id);

CREATE TABLE IF NOT EXISTS internal.comments (
  id SERIAL PRIMARY KEY,
  content TEXT NOT NULL,
  post_id INTEGER NOT NULL REFERENCES internal.posts(id),
  user_id UUID NOT NULL REFERENCES manati_auth.users(id)
);
SELECT manati_utils.create_timestamps('internal.comments');
CREATE INDEX comments_user_id_idx ON internal.comments(user_id);
CREATE INDEX comments_post_id_idx ON internal.comments(post_id);

CREATE TABLE IF NOT EXISTS internal.questions (
  id INTEGER PRIMARY KEY,
  title VARCHAR NOT NULL,
  slug VARCHAR NOT NULL CONSTRAINT url CHECK (slug ~ '[a-z0-9]{3,}'),
  tags VARCHAR[] NOT NULL,
  post_id INTEGER NOT NULL REFERENCES internal.posts(id)
);
SELECT manati_utils.create_timestamps('internal.questions');
CREATE INDEX question_tags_gin ON internal.questions USING GIN (tags);
CREATE INDEX question_post_idx ON internal.questions (post_id);

CREATE TABLE IF NOT EXISTS internal.answers (
  post_id INTEGER NOT NULL REFERENCES internal.posts(id),
  question_id INTEGER NOT NULL,
  PRIMARY KEY(post_id)
);
SELECT manati_utils.create_timestamps('internal.answers');
CREATE INDEX answer_question_id ON internal.answers(question_id);

DROP VIEW IF EXISTS api.questions;
CREATE OR REPLACE VIEW api.questions AS
  SELECT q.id, q.title, q.slug, q.tags, p.content, p.vote, u.app_id::int as author_id, u.data->>'username' as author,
  GREATEST(p.updated_at, q.updated_at) as updated_at, q.created_at
  FROM internal.questions q
  JOIN internal.posts p ON p.id = q.post_id
  JOIN manati_auth.users u ON u.id = p.user_id
  GROUP BY q.id, p.id, u.id;

DROP VIEW IF EXISTS api.comments;
CREATE OR REPLACE VIEW api.comments AS
  SELECT c.id, c.content, u.app_id::int as author_id, u.data->>'username' as author, c.updated_at, c.created_at
  FROM internal.comments c
  JOIN manati_auth.users u ON u.id = c.user_id;


CREATE OR REPLACE FUNCTION api.update_questions() RETURNS trigger AS $$
BEGIN
  EXECUTE concat(manati_utils.create_update_query('internal', 'questions', ARRAY['title', 'slug', 'tags']), ' WHERE id = $2') using NEW, OLD.id;
  EXECUTE concat(manati_utils.create_update_query('internal', 'posts', ARRAY['vote', 'content']), ' FROM internal.questions q WHERE q.id = $2 AND q.post_id = internal.posts.id') using NEW, OLD.id;
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql' SECURITY DEFINER;

CREATE TRIGGER update_questions INSTEAD OF
  UPDATE ON api.questions FOR EACH ROW EXECUTE PROCEDURE api.update_questions();

CREATE OR REPLACE FUNCTION api.update_answers() RETURNS trigger AS $$
BEGIN
  EXECUTE concat(manati_utils.create_update_query('internal', 'posts', ARRAY['content', 'vote']), ' FROM internal.posts p WHERE p.question_id = $2 AND p.id = a.post_id') using NEW, OLD.id;
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql' SECURITY DEFINER;

CREATE TRIGGER update_questions INSTEAD OF
  UPDATE ON api.answers FOR EACH ROW EXECUTE PROCEDURE api.update_answers();


CREATE OR REPLACE FUNCTION api.insert_questions() RETURNS trigger AS $$
DECLARE _question record;
DECLARE _post record;
BEGIN
  INSERT INTO internal.posts (content, user_id) VALUES (NEW.content, manati_auth.current_manati_user()) RETURNING * INTO _post;
  INSERT INTO internal.questions (title, slug, tags, post_id) VALUES (NEW.title, NEW.slug, NEW.tags, _post.id) RETURNING * INTO _question;

  SELECT * INTO NEW from api.questions WHERE id = _question.id;

  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql' SECURITY DEFINER;

CREATE TRIGGER insert_questions INSTEAD OF
  INSERT ON api.questions FOR EACH ROW EXECUTE PROCEDURE api.insert_questions();


DROP VIEW IF EXISTS api.answers;
CREATE OR REPLACE VIEW api.answers AS
  SELECT p.content, u.app_id::int as author_id, u.data->>'username' as author, a.question_id,
  p.vote, p.updated_at, p.created_at
   FROM internal.answers a
   JOIN internal.posts p ON p.id = a.post_id
   JOIN manati_auth.users u ON u.id = p.user_id
   GROUP BY p.id, p.id, u.id, a.question_id;

CREATE OR REPLACE VIEW api.tags AS SELECT DISTINCT unnest(tags) as name FROM internal.questions;


COMMIT;
