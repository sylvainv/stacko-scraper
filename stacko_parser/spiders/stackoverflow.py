# -*- coding: utf-8 -*-
import scrapy
import os
from stacko_parser.items import Question
import html2text
import re

class StackoverflowSpider(scrapy.Spider):
    name = "stackoverflow"
    allowed_domains = ["stackoverflow.com"]

    start_urls = []
    for page in range(0, 65000):
        start_urls.append('http://stackoverflow.com/questions?sort=active&page=' + str(page))

    def parse(self, response):
        self.logger.info('A response from %s just arrived!', response.url)

        for url in response.css('.question-hyperlink').xpath('@href'):
            yield scrapy.Request(response.urljoin(url.extract()), self.parse_question)

    def parse_answer(self, selector):
        owner = selector.css('.post-signature')
        userurl = selector.css('.post-signature a').xpath('@href').extract().pop()
        created_at = owner.css('.relativetime').xpath('@title').extract().pop()
        last_edittime = selector.css('.post-signature').xpath('a[@href="*/revisions"]/span[@class="relativetime"]').xpath('@title').extract()

        user_search = re.search('^/users/([0-9]+)/', userurl, re.IGNORECASE)
        item = {
            'description': html2text.html2text(selector.css('div.post-text').extract().pop()),
            'vote': int(selector.css('.vote-count-post::text').extract().pop()),

            'created_at': created_at,
            'updated_at': created_at if len(last_edittime) == 0 else last_edittime.pop(),

            'user': {
                'name': os.path.basename(userurl),
                'id': user_search.group(1) if user_search  else 0
            },
            'comments': []
        }

        comments_selector = selector.css('.comments .comment')
        for comment in comments_selector:
            comment_text_selector = comment.css('.comment-text')
            userurl = comment_text_selector.css('.comment-body .comment-user').xpath('@href').extract().pop()
            comment_date = comment_text_selector.css('.comment-body .comment-date span').xpath('@title').extract().pop()

            user_search = re.search('^/users/([0-9]+)/', userurl, re.IGNORECASE)
            c = {
                'id': int(comment.xpath('@id').extract().pop().split('-')[1]),
                'text': html2text.html2text(comment.css('.comment-text .comment-body .comment-copy').extract().pop()),
                'user': {
                    'name': os.path.basename(userurl),
                    'id': user_search.group(1) if user_search  else 0
                },
                'updated_at': comment_date,
                'created_at': comment_date
            }
            item['comments'].append(c)

        return item

    def parse_question(self, response):
        question = response.css('div.question')

        item = self.parse_answer(response.css('div.question'))

        titleSelector = response.css('#question-header h1')

        item['id'] = question.xpath('@data-questionid').extract().pop()
        item['title'] = titleSelector.css('a::text').extract().pop()
        item['url'] = titleSelector.css('a').xpath('@href').extract().pop()
        item['slug'] = os.path.basename(item['url'])
        item['answers'] = []
        item['tags'] = response.css('.post-taglist').css('.post-tag::text').extract()

        answers_selector = response.css('#answers .answer')
        for answer_selector in answers_selector:
            answer = self.parse_answer(answer_selector)
            answer['id'] = answer_selector.xpath('@data-answerid').extract().pop()
            item['answers'].append(answer)

        return item
