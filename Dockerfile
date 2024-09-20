FROM public.ecr.aws/lambda/python:3.11
RUN yum -y install make zip unzip
ENTRYPOINT [ ]