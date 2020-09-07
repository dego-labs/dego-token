echo "deploy begin....."

TF_CMD=node_modules/.bin/truffle-flattener

TOKEN_LIST=(DegoToken DegoOpenSale)

for contract in ${TOKEN_LIST[@]};
do
    echo $contract
    echo "" >  ./deployments/$contract.full.sol
    cat  ./scripts/head.sol >  ./deployments/$contract.full.sol
    $TF_CMD ./contracts/token/$contract.sol >>  ./deployments/$contract.full.sol 
done

# rm *_sol_*

echo "deploy end....."