# Copyright 2019 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

from oslo_log import log as oslo_logging

from cloudbaseinit import conf as cloudbaseinit_conf
from cloudbaseinit.metadata.services import base

CONF = cloudbaseinit_conf.CONF
LOG = oslo_logging.getLogger(__name__)

GCE_HEADERS = {'Metadata-Flavor': 'Google'}


class GCEService(base.BaseHTTPMetadataService):

    def __init__(self):
        super(GCEService, self).__init__(
            base_url=CONF.gce.metadata_base_url,
            https_allow_insecure=CONF.gce.https_allow_insecure,
            https_ca_bundle=CONF.gce.https_ca_bundle)
        self._enable_retry = True
        self._instance_path = 'instance'
        self._project_path = 'project'
        self._instance_attributes_path = '%s/attributes' % self._instance_path
        self._project_attributes_path = '%s/attributes' % self._project_path

    def _http_request(self, url, data=None, headers=None, method=None):
        if not headers:
            headers = GCE_HEADERS
        else:
            headers.update(GCE_HEADERS)
        return super(GCEService, self)._http_request(url, data,
                                                     headers, method)

    def load(self):
        super(GCEService, self).load()

        try:
            self.get_host_name()
            return True
        except Exception as ex:
            LOG.exception(ex)
            LOG.debug('Metadata not found at URL \'%s\'' %
                      CONF.gce.metadata_base_url)
            return False

    def get_host_name(self):
        return self._get_cache_data('%s/name' % self._instance_path,
                                    decode=True)

    def get_instance_id(self):
        return self._get_cache_data('%s/id' % self._instance_path,
                                    decode=True)

    def get_user_data(self):
        return self._get_cache_data(
            '%s/user-data' % self._instance_attributes_path)

