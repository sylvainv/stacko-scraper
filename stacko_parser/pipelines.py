# -*- coding: utf-8 -*-

# Define your item pipelines here
#
# Don't forget to add your pipeline to the ITEM_PIPELINES setting
# See: http://doc.scrapy.org/en/latest/topics/item-pipeline.html
import json
import pgdb
import urlparse

class StackoParserPipeline(object):

    def __init__(self, database_url):
        self.database_url = database_url

    @classmethod
    def from_crawler(cls, crawler):
        return cls(database_url=crawler.settings.get('DATABASE_URL'))

    def open_spider(self, spider):
        u = urlparse.urlparse(self.database_url)
        self.client = pgdb.connect(
            database=u.path[1:], host=u.hostname, user=u.username, password=u.password
        )

    def close_spider(self, spider):
        self.client.close()

    def process_item(self, item, spider):
        cur = self.client.cursor()

        post_id = self.add_post(cur, item)
        item['post_id'] = post_id
        item['tags'] = '{"' + ('","'.join(str(v) for v in item['tags'])) + '"}'

        cur.execute("INSERT INTO internal.questions (id, post_id, title, slug, tags, created_at, updated_at) VALUES (%(id)s, %(post_id)s, %(title)s, %(slug)s, %(tags)s, %(created_at)s, %(updated_at)s)", item);
        question_id = item['id']

        for answer in item['answers']:
            post_id = self.add_post(cur, answer)
            cur.execute("INSERT INTO internal.answers (post_id, question_id,  created_at, updated_at) VALUES (%s, %s, %s, %s);", (post_id, question_id, answer['created_at'], answer['updated_at']));

        self.client.commit()
        cur.close()


    def add_post(self, cur, data):
        data['user_id'] = data['user']['id']
        cur.execute("INSERT INTO internal.users (id, username) VALUES (%s, %s) ON CONFLICT ON CONSTRAINT users_pkey DO NOTHING;", (data['user']['id'], data['user']['name']))
        cur.execute("INSERT INTO internal.posts (content, vote, user_id, created_at, updated_at) VALUES ( %(description)s, %(vote)s, %(user_id)s, %(created_at)s, %(updated_at)s) RETURNING id;", data);

        post_id = cur.fetchone()

        for comment in data['comments']:
            comment['post_id'] = post_id
            comment['user_id'] = comment['user']['id']

            cur.execute("INSERT INTO internal.users (id, username) VALUES (%s, %s) ON CONFLICT ON CONSTRAINT users_pkey DO NOTHING;", (comment['user']['id'], comment['user']['name']));
            cur.execute(
              "INSERT INTO internal.comments (content, user_id, post_id, created_at, updated_at) VALUES (%(text)s, %(user_id)s, %(post_id)s, %(created_at)s, %(updated_at)s);",
              comment
            )

        return post_id;
