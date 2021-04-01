simulatorURL="http://$(oc get route vaccine-reefer-simulator -o jsonpath='{.status.ingress[0].host}')"
echo "User Interface of the simulator is available via $simulatorURL"

freezerURL="http://$(oc get route freezer-mgr -o jsonpath='{.status.ingress[0].host}')"
echo "User Interface of the Freezer manager is available via $freezerURL"

monitoringAgentURL="http://$(oc get route reefer-monitoring-agent -o jsonpath='{.status.ingress[0].host}')"

echo "User Interface of the Monitoring Agent is available via $monitoringAgentURL"



echo "-----------------------------"
echo " Test Freezer Mgr response "
echo "-----------------------------"
curl -X GET $freezerURL/reefers

echo "-----------------------------"
echo " Test Simulator Mgr response"
echo "-----------------------------"
curl -X GET $simulatorURL/health

echo "-----------------------------"
echo " Test Monitoring Agent Mgr response"
echo "-----------------------------"
curl -X GET $monitoringAgentURL/q/health