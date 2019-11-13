# SPDX-License-Identifier: MIT
FROM node:13

RUN npm install --global remark-cli remark-validate-links remark-lint-no-dead-urls

WORKDIR /github/workspace

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
