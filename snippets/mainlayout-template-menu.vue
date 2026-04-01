 <span class="text-grey-5">(fe: {{ feVersion }})</span>
            <q-menu context-menu @before-show="loadFrontendVersions">
              <q-list dense style="min-width: 220px">
                <q-item-label header>Frontend Versions</q-item-label>
                <q-separator />
                <q-item
                  v-for="ver in frontendVersions"
                  :key="ver.name"
                  v-close-popup
                  clickable
                  :active="ver.active"
                  active-class="text-positive"
                  @click="switchFrontendVersion(ver.name)"
                >
                  <q-item-section side>
                    <q-icon
                      :name="ver.active ? 'check_circle' : 'radio_button_unchecked'"
                      :color="ver.active ? 'positive' : 'grey'"
                      size="xs"
                    />
                  </q-item-section>
                  <q-item-section>{{ ver.name }}</q-item-section>
                </q-item>
                <q-item v-if="frontendVersions.length === 0">
                  <q-item-section class="text-grey">No versions found</q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </span>
