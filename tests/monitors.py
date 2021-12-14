from datetime import datetime, timedelta
import subprocess
import numpy as np
import pandas as pd
import json

from confluent_kafka import Consumer

import kafka_tools as kt

conf = {
    'bootstrap.servers': 'vaccine-kafka-kafka-bootstrap-trumbell.o7-111a9c298953d78649164b7e8394bcdc-0000.us-south.containers.appdomain.cloud:443',
    'security.protocol': 'SASL_SSL',
    'ssl.ca.location': 'certs/ca.crt',
#     'ssl.keystore.location': 'user-keystore.jks',
#     'ssl.keystore.password': 'changeit',
#     'ssl.key.location': 'user.key',
#     'ssl.key.password': 'abcdefgh',
#     'ssl.certificate.location': 'user.crt',
    'sasl.mechanisms': 'SCRAM-SHA-512',
    'sasl.username': 'scram-user',
    'sasl.password': 'cp6aYMO0BHbg',
#     'enable.ssl.certificate.verification': 'false'
#     'api.version.request': 'true'
    'auto.offset.reset': 'earliest'
}
processing_time_topic = 'reefer.telemetries.processedtime'
telemetry_topic = 'reefer.telemetries'
log_datemask = "%Y-%m-%d %H:%M:%S.%f"
processed_datemask = "%Y-%m-%dT%H:%M:%S.%f"
deployments = {'OS': {'context': 'trumbell/c114-e-us-south-containers-cloud-ibm-com:30501/IAM#thrumbel@us.ibm.com',
                      'dep_name': 'reefer-monitoring-agent',
                      'priority': 0,
                      'max_replicas': 80,
                      'min_replicas': 1},
                'CE': {'context': 'gevokcvgseu',
                      'dep_name': 'vaccine-monitoring-agent',
                      'priority': 1,
                      'max_replicas': 0,
                      'min_replicas': 0}}
targets = {'single_event_processing_time': 0.5,
           'target_delay': 120.,
           'ramp_delay': 10.,
           'target_lag': 480,
           'ramp_lag': 240}

class ProcessingTimeMonitor():
    def __init__(self, kafka_config=conf, processing_time_topic=processing_time_topic, 
                       group_id='delay', log_datemask=log_datemask,
                       processed_datemask=processed_datemask):
        self._conf = kafka_config
        self._topic = processing_time_topic
        self._group_id = group_id
        self._log_datemask = log_datemask
        self._processed_datemask = processed_datemask
        self._df = self.init_df()
        self._c = self.init_consumer(self._conf, group_id=self._group_id)

    def init_consumer(self, conf, group_id=None):
        if group_id:
            conf.update({'group.id': group_id})
        c = Consumer(conf)
        return c

    def init_df(self):
        df = pd.DataFrame(columns=['time','eventLogTime','eventProcessedTime','delay'])
        return df

    def update_df_from_kafka(self):
        update_time = datetime.utcnow()
        messages = kt.consume_to_end_of_topic(self._c, [self._topic])
        if messages:
            msg_values = [json.loads(msg.value()) for msg in messages]
            update_df = pd.DataFrame(msg_values)
            update_df['delay'] = update_df.apply(
                lambda x: (datetime.strptime(x['eventProcessedTime'], self._processed_datemask) - 
                           datetime.strptime(x['eventLogTime'], self._log_datemask)).total_seconds(),
                axis=1
            )
            update_df['time'] = update_time
            new_df = self._df.append(update_df, ignore_index=True)
            self._df = new_df
        else:
            update_df = pd.DataFrame([[0.0, update_time]], columns=['delay', 'time'])
            new_df = self._df.append(update_df, ignore_index=True)
            self._df = new_df

    def shutdown(self):
        self._c.close()
    

class ConsumerOffsetMonitor():
    def __init__(self, kafka_config=conf, telemetry_topic=telemetry_topic, 
                       group_id='cold-chain-agent'):
        self._conf = kafka_config
        self._topic = telemetry_topic
        self._group_id = group_id
        self._df = self.init_df()
        self._c = self.init_consumer(self._conf, group_id=self._group_id)
        self._c.close()

    def init_consumer(self, conf, group_id=None):
        if group_id:
            conf.update({'group.id': self._group_id,
                         'enable.auto.commit': False})
        c = Consumer(conf)
        return c

    def init_df(self):
        df = pd.DataFrame(columns=['id','watermark','new_msgs','msgs_per_sec',
                                   'committed','lag','time'])
        return df

    def get_offset_lag_for_consumer(self, consumer, topics=[]):
        partitions = kt.get_partitions_for_consumer(consumer, topics)
        ids = range(len(partitions))
        watermarks = [consumer.get_watermark_offsets(part)[1] for part in partitions]
        committeds = [np.max([0, part.offset]) for part in consumer.committed(partitions)]
        offset_df = pd.DataFrame(list(zip(ids, watermarks, committeds)), 
                                 columns=['id', 'watermark', 'committed'])
        offset_df['lag'] = offset_df['watermark'] - offset_df['committed']
        offset_df['time'] = datetime.utcnow()
        return offset_df

    def update_df_from_kafka(self, aggregate_df=True):
        self._c = self.init_consumer(self._conf, group_id=self._group_id)
        offsets = self.get_offset_lag_for_consumer(consumer=self._c, topics=self._topic)
        self._c.close()
        if aggregate_df:
            if self._df.shape[0] > 0:
                new_msgs = offsets['watermark'].sum() - self._df.iloc[-1]['watermark']
                time_diff = (offsets.iloc[0]['time'] - self._df.iloc[-1]['time']).total_seconds()
                msgs_per_sec = new_msgs / time_diff
            else:
                new_msgs = 0
                msgs_per_sec = 0
            offsets = pd.DataFrame([['all', 
                                    offsets['watermark'].sum(), 
                                    new_msgs,
                                    msgs_per_sec,
                                    offsets['committed'].sum(),
                                    offsets['lag'].sum(),
                                    offsets.iloc[0]['time']]],
                                    columns=['id','watermark','new_msgs','msgs_per_sec',
                                             'committed','lag','time'])
        new_offsets = self._df.append(offsets, ignore_index=True)
        self._df = new_offsets

    def shutdown(self):
        self._c.close()


class AgentReplicasMonitor():
    def __init__(self, deployments=deployments, targets=targets, n_scale_hist=10):
        self._deployments = deployments
        self._targets = targets
        self._df = self.init_df()
        self._n_scale_hist = n_scale_hist
        self._scale_history = []

    def init_df(self):
        df = pd.DataFrame(columns=['time', 'name', 'scale'])
        return df

    def get_deployment_scale(self, context, name):
        subprocess.run(['kubectl', 'config', 'use-context', context], capture_output=True)
        scale = subprocess.run(
            ['kubectl get deployment {} | awk \'FNR==2 {{print $4}}\''.format(name)], 
            shell=True, text=True, capture_output=True
        )
        # print(scale)
        return int(scale.stdout)

    def scale_deployment(self, context, name, scale):
        subprocess.run(['kubectl', 'config', 'use-context', context], capture_output=True)
        output = subprocess.run(
           # ['kubectl patch deployment {0} -p \'{{"spec": {{"replicas": {1}}}}}\''.format(name, scale)], 
           ['kubectl scale deployment {0} --replicas {1}'.format(name, scale)], 
            shell=True, text=True, capture_output=True
        )
        return output

    def update_df(self):
        update_time = datetime.utcnow()
        update_list = []
        for name, dep in self._deployments.items():
            scale = self.get_deployment_scale(dep['context'], dep['dep_name'])
            update_list.append({'time': update_time, 'name': name, 'scale': scale})
        update_df = pd.DataFrame(update_list, columns=['time', 'name', 'scale'])
        new_df = self._df.append(update_df, ignore_index=True)
        self._df = new_df

    def change_deployment_scales(self, method='rate',
                                 current_delay=0, current_lag=0, current_rate=0):
        curr_scale = {}
        # update internal dataframe if it hasn't been checked recently
        if ((datetime.utcnow() - timedelta(seconds=300)) > self._df.iloc[-1]['time']):
            self.update_df()
        # add scale info for each deployment to curr_scale
        [curr_scale.update({key: {'priority': val['priority'], 
                                  'scale': self._df[self._df['name']==key].iloc[-1].scale}})
                            for key, val in self._deployments.items()]
        # get total scaling across all deployments
        total_scale = sum([val['scale'] for val in curr_scale.values()])
        
        change_scale_delay = int(np.ceil((current_delay - targets['target_delay'])/targets['ramp_delay']))
        change_scale_lag = int(np.ceil((current_lag - targets['target_lag'])/targets['ramp_lag']))
        # Scale based on rate requires msgs_per_seconds * processing_time replicas
        change_scale_rate = int(np.ceil(targets['single_event_processing_time'] * current_rate))

        if method == 'delay':
            target_scale = total_scale + change_scale_delay
        elif method == 'lag':
            target_scale = total_scale + change_scale_lag
        elif method == 'rate':
            target_scale = change_scale_rate
        elif method == 'max':
            # scale based on multiple considerations - if there is a large message rate, or delay or lag are too high
            target_scale = np.max([(total_scale + change_scale_delay), 
                                   (total_scale + change_scale_lag),
                                    change_scale_rate])
        # target_scale = total_scale + np.max([change_scale_delay, change_scale_lag])
        # print("Total scale: {0}; change_scale_delay: {1}; change_scale_lag: {2}; target_scale {3}".format(
        #     total_scale, change_scale_delay, change_scale_lag, change_scale_lag
        # ))

        # Keep track of previous n_scale_hist scales, to prevent scaling down occuring too rapidly
        self._scale_history.append(target_scale)
        while len(self._scale_history) > self._n_scale_hist:
            self._scale_history.pop(0)
        target_scale = max(self._scale_history)
        
        # Distribute target scale across nodes in order of priority
        priorities = {}
        [priorities.update({val['priority']: key}) for key, val in self._deployments.items()]
        for ii in range(len(self._deployments)):
            curr_dep_name = priorities[ii]
            curr_dep = self._deployments[curr_dep_name]
            new_scale = np.max([np.min([target_scale, curr_dep['max_replicas']]), curr_dep['min_replicas']])
            print("Setting scale for {0} to {1}".format(curr_dep_name, new_scale))
            self.scale_deployment(
                context=curr_dep['context'],
                name=curr_dep['dep_name'],
                scale=new_scale
            )
            target_scale = target_scale - new_scale
