FROM registry.theopencloset.net/opencloset/perl:latest

RUN groupadd opencloset && useradd -g opencloset opencloset

WORKDIR /tmp
COPY cpanfile cpanfile
RUN cpanm --notest \
    --mirror http://www.cpan.org \
    --mirror http://cpan.theopencloset.net \
    --installdeps .

# Everything up to cached.
WORKDIR /home/opencloset/service/OpenCloset-Cron-Event
COPY . .
RUN chown -R opencloset:opencloset .

USER opencloset

ENV PERL5LIB "./lib:$PERL5LIB"

CMD ["./bin/opencloset-cron-event.pl", "./app.conf"]

EXPOSE 5000
