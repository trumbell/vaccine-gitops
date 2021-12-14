import sys

from confluent_kafka import TopicPartition, KafkaError, KafkaException

def print_assignment(consumer, partitions):
    print('Assignment:', partitions)

def get_partitions_for_consumer(consumer, topics_to_check=[]):
    # get all topics
    topics = consumer.list_topics()

    # get all partitions
    partitions = []
    for name, meta  in topics.topics.items():
        if name in topics_to_check:
            for partition_id in meta.partitions.keys():
                part = TopicPartition(name, partition_id)
                partitions.append(part)

    # get last committed offsets
#     partitions = consumer.committed(partitions)
    return partitions

def consume_to_end_of_topic(c, topic):
    messages = []
    msg_count = 0
    MIN_COMMIT_COUNT = 200
    
    c.subscribe(topic) #, on_assign=print_assignment)
    # Longer poll for first message as it might take a little bit to assign the consumer to partitions
    msg = c.poll(timeout=10.)
    try:
        if msg == None: pass
        elif msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                # End of partition event
                sys.stderr.write('%% %s [%d] reached end at offset %d\n' %
                                 (msg.topic(), msg.partition(), msg.offset()))
            elif msg.error():
                raise KafkaException(msg.error())
        else:
            messages.append(msg)
            msg_count += 1
            if msg_count % MIN_COMMIT_COUNT == 0:
                c.commit(asynchronous=False)
    except:
        raise

    while msg is not None:
        try:
            msg = c.poll(timeout=.1)
            if msg == None: break
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    # End of partition event
                    sys.stderr.write('%% %s [%d] reached end at offset %d\n' %
                                     (msg.topic(), msg.partition(), msg.offset()))
                    break
                elif msg.error():
                    raise KafkaException(msg.error())
            else:
                messages.append(msg)
                msg_count += 1
                if msg_count % MIN_COMMIT_COUNT == 0:
                    c.commit(asynchronous=False)
        except:
            raise
    
    return messages

