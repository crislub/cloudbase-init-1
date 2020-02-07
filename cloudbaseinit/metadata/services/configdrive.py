# Copyright 2012 Cloudbase Solutions Srl
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

import os
import shutil

from oslo_log import log as oslo_logging

from cloudbaseinit import conf as cloudbaseinit_conf
from cloudbaseinit import constant
from cloudbaseinit import exception
from cloudbaseinit.metadata.services import base
from cloudbaseinit.metadata.services import baseopenstackservice
from cloudbaseinit.metadata.services.osconfigdrive import base as basecd
from cloudbaseinit.metadata.services.osconfigdrive import factory

CONF = cloudbaseinit_conf.CONF
LOG = oslo_logging.getLogger(__name__)

CD_TYPES = constant.CD_TYPES
CD_LOCATIONS = constant.CD_LOCATIONS


class BaseConfigDriveService(base.BaseMetadataService):

    def __init__(self, config_type):
        super(BaseConfigDriveService, self).__init__()
        self._config_type = config_type
        self._metadata_path = None
        self._searched_types = None
        self._searched_locations = None

    def _get_config_options(self):
        return CONF.config_drive

    def _preprocess_options(self):
        config_options = self._get_config_options()

        self._searched_types = set(config_options.types)
        self._searched_locations = set(config_options.locations)

        # Deprecation backward compatibility.
        if config_options.raw_hdd:
            self._searched_types.add("iso")
            self._searched_locations.add("hdd")
        if config_options.cdrom:
            self._searched_types.add("iso")
            self._searched_locations.add("cdrom")
        if config_options.vfat:
            self._searched_types.add("vfat")
            self._searched_locations.add("hdd")

        # Check for invalid option values.
        if self._searched_types | CD_TYPES != CD_TYPES:
            raise exception.CloudbaseInitException(
                "Invalid Config Drive types %s", self._searched_types)
        if self._searched_locations | CD_LOCATIONS != CD_LOCATIONS:
            raise exception.CloudbaseInitException(
                "Invalid Config Drive locations %s", self._searched_locations)

    def load(self):
        super(BaseConfigDriveService, self).load()

        self._preprocess_options()
        self._mgr = factory.get_config_drive_manager()
        found = self._mgr.get_config_drive_files(
            searched_types=self._searched_types,
            searched_locations=self._searched_locations,
            config_type=self._config_type)

        if found:
            self._metadata_path = self._mgr.target_path
            LOG.info('Metadata copied to folder: %r', self._metadata_path)
        return found

    def _get_data(self, path):
        norm_path = os.path.normpath(os.path.join(self._metadata_path, path))
        try:
            with open(norm_path, 'rb') as stream:
                return stream.read()
        except IOError:
            raise base.NotExistingMetadataException()

    def cleanup(self):
        LOG.debug('Deleting metadata folder: %r', self._mgr.target_path)
        shutil.rmtree(self._mgr.target_path, ignore_errors=True)
        self._metadata_path = None


class ConfigDriveService(BaseConfigDriveService,
                         baseopenstackservice.BaseOpenStackService):

    def __init__(self):
        super(ConfigDriveService, self).__init__(
            config_type=basecd.CONFIG_DRIVE)


class NoCloudConfigDriveService(BaseConfigDriveService):

    def __init__(self):
        super(NoCloudConfigDriveService, self).__init__(
            config_type=basecd.NOCLOUD_CONFIG_DRIVE)
        self._meta_data = {}

    def get_user_data(self):
        return self._get_cache_data("user-data")

    def _get_meta_data(self):
        if self._meta_data:
            return self._meta_data

        raw_meta_data = self._get_cache_data("meta-data", decode=True)
        try:
            self._meta_data = self._parse_data(raw_meta_data)
        except Exception:
            LOG.warning("Metadata could not be parsed")

        return self._meta_data

    def get_host_name(self):
        return self._get_meta_data().get('local-hostname')

    def get_instance_id(self):
        return self._get_meta_data().get('instance-id')

    def get_public_keys(self):
        raw_ssh_keys = self._get_meta_data().get('public-keys')
        if not raw_ssh_keys:
            return []

        return [raw_ssh_keys[key].get('openssh-key') for key in raw_ssh_keys]
