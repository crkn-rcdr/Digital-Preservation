FROM perl:5.18.2

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
    mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr && \
    groupadd -g 1115 cihm && useradd -u 1015 -g cihm -m cihm && \ 
    ln -s /home/tdr /etc/canadiana/wip

WORKDIR /home/tdr
COPY cpanfile* *.conf *.xml /home/tdr/

# Our application is perl code, which we added to a local PINTO server as modules.  Other dependencies are from CPAN.
ENV PERL_CPANM_OPT "--mirror http://pinto.c7a.ca/stacks/c7a-perl-devel/ --mirror http://www.cpan.org/"
RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)

USER tdr

