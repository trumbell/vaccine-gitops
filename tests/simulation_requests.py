import asyncio

import aiohttp
from aiohttp import ClientSession, ClientConnectorError
import numpy as np
import json

import logging
logging.basicConfig(level=logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
#handler.setFormatter(formatter)
log = logging.getLogger()

HTTP_STATUS_CODES_TO_RETRY = [500, 502, 503, 504]

class FailedRequest(Exception):
    """
    A wrapper of all possible exception during a HTTP request
    """
    code = 0
    message = ''
    url = ''
    raised = ''

    def __init__(self, *, raised='', message='', code='', url=''):
        self.raised = raised
        self.message = message
        self.code = code
        self.url = url

        super().__init__("code:{c} url={u} message={m} raised={r}".format(
            c=self.code, u=self.url, m=self.message, r=self.raised))


async def send_http(session, method, url, *,
                    retries=2,
                    interval=0.9,
                    backoff=3,
                    http_status_codes_to_retry=HTTP_STATUS_CODES_TO_RETRY,
                    **kwargs):
    """
    Sends a HTTP request and implements a retry logic.

    Arguments:
        session (obj): A client aiohttp session object
        method (str): Method to use
        url (str): URL for the request
        retries (int): Number of times to retry in case of failure
        interval (float): Time to wait before retries
        backoff (int): Multiply interval by this factor after each failure
    """
    backoff_interval = interval
    raised_exc = None
    attempt = 0

    if method not in ['get', 'patch', 'post']:
        raise ValueError

    if retries == -1:  # -1 means retry indefinitely
        attempt = -1
    elif retries == 0: # Zero means don't retry
        attempt = 1
    else:  # any other value means retry N times
        attempt = retries + 1

    while attempt != 0:
        if raised_exc:
            log.error('caught "%s" url:%s method:%s, remaining tries %s, '
                    'sleeping %.2fsecs', raised_exc, method.upper(), url,
                    attempt, backoff_interval)
            await asyncio.sleep(backoff_interval)
            # bump interval for the next possible attempt
            backoff_interval = backoff_interval * backoff
        log.info('sending %s %s with %s', method.upper(), url, kwargs)
        try:
            async with getattr(session, method)(url, **kwargs) as response:
                if response.status == 201:
                    try:
                        data = await response.json()
                    except json.decoder.JSONDecodeError as exc:
                        log.error(
                            'failed to decode response code:%s url:%s '
                            'method:%s error:%s response:%s',
                            response.status, url, method.upper(), exc,
                            response.reason
                        )
                        raise aiohttp.errors.HttpProcessingError(
                            code=response.status, message=exc.msg)
                    else:
                        log.info('code:%s url:%s method:%s response:%s',
                                response.status, url, method.upper(),
                                response.reason)
                        raised_exc = None
                        return (url, response.status, data)
                elif response.status in http_status_codes_to_retry:
                    log.error(
                        'received invalid response code:%s url:%s error:%s'
                        ' response:%s', response.status, url, '',
                        response.reason
                    )
                    # raise aiohttp.errors.HttpProcessingError(
                    #     code=response.status, message=response.reason)
                else:
                    try:
                        data = await response.json()
                    except json.decoder.JSONDecodeError as exc:
                        log.error(
                            'failed to decode response code:%s url:%s '
                            'error:%s response:%s', response.status, url,
                            exc, response.reason
                        )
                        raise FailedRequest(
                            code=response.status, message=exc,
                            raised=exc.__class__.__name__, url=url)
                    else:
                        log.warning('received %s for %s', data, url)
                        # print(data['errors'][0]['detail'])
                        raised_exc = None
        except (aiohttp.ClientResponseError,
                aiohttp.ClientOSError,
                aiohttp.ServerDisconnectedError,
                aiohttp.ServerTimeoutError,
                asyncio.TimeoutError,
                aiohttp.ClientPayloadError) as exc:
            try:
                code = exc.code
            except AttributeError:
                code = ''
            raised_exc = FailedRequest(code=code, message=exc, url=url,
                                    raised=exc.__class__.__name__)
        else:
            raised_exc = None
            break

        attempt -= 1

    if raised_exc:
        raise raised_exc


async def fetch_html(url: str, params, session: ClientSession, **kwargs) -> tuple:
    resp = None
    try:
        resp = await session.request(method="GET", url=url, params=params, **kwargs)
        content = await resp.json()
    except ClientConnectionError:
        return (url, 404)
    return (url, resp.status, content)


async def make_requests(url:str, datasets: set, **kwargs) -> tuple:
    timeout = aiohttp.ClientTimeout(total=10*60)
    async with ClientSession(timeout=timeout) as session:
        tasks = []
        for json_payload in datasets:
            tasks.append(
                # fetch_html(url=url, params=params, session=session, **kwargs)
                send_http(session=session, method='post', url=url, json=json_payload, **kwargs)
            )
        results = await asyncio.gather(*tasks)
    
    # for result in results:
    #     print(f'{result[1]} - {str(result[0])}')

    return results


if __name__ == "__main__":
    import pathlib
    import sys
    import time

    assert sys.version_info >= (3, 7), "Script requires Python 3.7+."
    here = pathlib.Path(__file__).parent

    n_containers = 200
    n_delay = 30
    min_delay = 0
    n_records = 1
    n_repeats = np.inf

    n_container_list = [100, 200, 100]
    n_repeats_list = [40, 40, 40]

    url = "http://vaccine-reefer-simulator-trumbell.o7-111a9c298953d78649164b7e8394bcdc-0000.us-south.containers.appdomain.cloud/control"
    
    jj = 0
    while (jj<len(n_container_list)):

        datasets = [{
            "containerID": "C000001", 
            "nb_of_records": n_records, 
            "product_id": "P01", 
            "simulation": "tempgrowth",
            "nb_in_batch": n_container_list[jj]
        }] # for container_name in [f'C{i:06}' for i in range(1,n_container_list[jj]+1)]]

        ii = 0
        while ii < n_repeats_list[jj]:
            start = time.time()
            results = asyncio.run(make_requests(url=url, datasets=datasets))
            stop = time.time()
            elapsed = stop-start
            print(elapsed)
            time.sleep(max(n_delay-elapsed, min_delay))
            ii = ii + 1

        jj = jj + 1
