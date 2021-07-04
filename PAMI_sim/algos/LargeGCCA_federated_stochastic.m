function [ Q, G ,obj,dist, St, time] = LargeGCCA_new( X,K, varargin )

    %MaxIt,G,Q,Li,EXTRA,WZW,norm_vec,vec_ind


    if (nargin-length(varargin)) ~= 2
        error('Wrong number of required parameters');
    end

    %--------------------------------------------------------------
    % Set the defaults for the optional parameters
    %--------------------------------------------------------------

    [~,I]=size(X);
    for i=1:I
    [L,M(i)]=size(X{i});
    end
    MaxIt = 1000;
    EXTRA = 0;
    Um = [];
    T = 2;
    L11=0; L21=0;r=0;
    Nbits = 3;
    sgd = false;
    %--------------------------------------------------------------
    % Read the optional parameters
    %--------------------------------------------------------------
    if (rem(length(varargin),2)==1)
        error('Optional parameters should always go by pairs');
    else
        for i=1:2:(length(varargin)-1)
            switch upper(varargin{i})
                case 'R'  % regularization parameter
                    r = varargin{i+1};
                case 'MAXIT'
                    MaxIt = varargin{i+1};
                case 'G_INI'
                    G = varargin{i+1};
                case 'Q_INI'
                    Q = varargin{i+1};
                case 'LI'
                    Li = varargin{i+1};
                case 'NORM_VEC' % vector for weighting/ normalization
                    norm_vec = varargin{i+1};
                case 'VEC_IND'
                    vec_ind = varargin{i+1}; % vec_ind(:,i) indicates which row is missing in Xi
                case 'ALGO_TYPE'
                    algo_type = varargin{i+1}; %'plain','centered','plain_fs' (fs: feature-selective)
                case 'INNER_IT'
                    T =  varargin{i+1};
                case 'EXTRA'
                    EXTRA =  varargin{i+1};
                case 'REG_TYPE'
                    REG_TYPE = varargin{i+1}; %'none','fro'
                case 'UM'
                    Um =  varargin{i+1}; % for measuring error
                case 'NBITS'
                    Nbits = varargin{i+1};
                case 'SGD'
                    sgd = varargin{i+1};
                case 'BATCH_SIZE'
                    batch_size = varargin{i+1};
                otherwise
                    % Hmmm, something wrong with the parameter string
                    error(['Unrecognized option: ''' varargin{i} '''']);
            end;
        end;
    end

    Nlevels = 2^(Nbits-1) - 1;

    switch REG_TYPE
        case 'none'
            r=0;
        case 'fro'
            r = r;
    end

    obj_temp = 0;
    switch REG_TYPE
        case 'fro'
            for i=1:I
                obj_temp =(1/2)*sum(sum(((1/sqrt(L))*X{i}*Q{i}-G).^2))+ (r/2)*sum(sum(Q{i}.^2)) + obj_temp;
            end
        case 'none'
            for i=1:I
                obj_temp =(1/2)*sum(sum(((1/sqrt(L))*X{i}*Q{i}-G).^2))+ obj_temp;
            end
    end
    obj_0=sum(obj_temp);

    if isempty(Um)~=1
        dist_0 = norm(Um'*G,2);
    else dist_0=[];
    end

    for i=1:I
        Li{i} = Li{i}+r;
    end

    M_quant = cell(I);
    M_diff = cell(I);
    M_serv = cell(I);
    normalizer = L;
    for i=1:I
        if sgd
            M_serv{i} = (1/sqrt(normalizer))*X{i}*Q{i};
        else
            M_serv{i} = (1/sqrt(L))*X{i}*Q{i};
        end
    end

    tic
    for it=1:MaxIt
        disp(['at iteration ',num2str(it)])
        if sgd
            for i=1:I
                batch_ind = randperm(L);
                batch = X{i};
                batch(batch_ind(1:L-batch_size), :) = 0;
                for inner_it=1:T % Gradient Descent
                    Q{i}=Q{i}-(5*1/Li{i})*((1/normalizer)*batch'*(batch*Q{i})+r*Q{i}-(1/sqrt(normalizer))*batch'*G);
                end
            end
        else
            for i=1:I  
                for inner_it=1:T % Gradient Descent
                    Q{i}=Q{i}-(1/Li{i})*((1/L)*X{i}'*(X{i}*Q{i})+r*Q{i}-(1/sqrt(L))*X{i}'*G);
                end    
            end
        end
        time(it) = toc;
        disp(['time gd: ', num2str(toc)]);    
        

        for i=1:I
            % variable to be transmitted
            if sgd
                XQ{i}= (1/sqrt(normalizer))*X{i}*Q{i};
            else
                XQ{i}= (1/sqrt(L))*X{i}*Q{i};
            end
            M_diff{i} = XQ{i} - M_serv{i};
            
            % use uniform symmetric quantization 
            max_val = max(abs(M_diff{i}),[], 'all');
            M_quant{i} = (round((Nlevels/max_val)*M_diff{i})*(max_val/Nlevels));
            
            % % use qsgd
            % M_quant{i} = qsgd(M_diff{i}, 0);
            
            % % sign quantize
            % M_quant{i} = (norm(M_diff{i},1)/(L*K))*sign(M_diff{i});
            
            % at the server
            M_serv{i} = M_serv{i} + M_quant{i};
        end


        M_temp = zeros(L,K);
        for i=1:i
            M_temp = M_temp + M_serv{i};
        end
        M_temp = M_temp/I;
        
        % SVD version - global optimality guaranteed
        [Ut,St,Vt]=svd(M_temp,0);
        G = Ut(:,1:K)*Vt';
        
        % time_acc(it)=sum(time_perit);
        
        obj_temp = 0;
        switch REG_TYPE
            case 'fro'
                for i=1:I
                    obj_temp =(1/2)*sum(sum(((1/sqrt(L))*X{i}*Q{i}-G).^2))+ (r/2)*sum(sum(Q{i}.^2)) + obj_temp;
                end
                obj(it)=sum(obj_temp);
            case 'none'
                for i=1:I
                    obj_temp =(1/2)*sum(sum(((1/sqrt(L))*X{i}*Q{i}-G).^2)) + obj_temp;
                end
                obj(it)=sum(obj_temp);
        end
        
        disp(['obj: ', num2str(obj(it))]);
        disp([' ']);
        
        if isempty(Um)~=1
            dist(it) = norm(Um'*G,2);
        else
            dist = [];
        end

        if it>1 && abs(obj(it)-obj(it-1))<1e-12
            break;
        end
        
        % file_name = ['/export/scratch2/xiao/PAMI_MAXVAR/evaluation/I4_M100/',REG_TYPE,'_svd_M100_K',num2str(K),'_iter_',num2str(it)];
        % save(file_name,'obj_0','obj','time_acc','Q','G','q_length')

        % for i=1:I
        % disp(['view_',num2str(i), ' obj_', num2str(obj(it))])
        % disp(['the sparsity is ',num2str(q_length(i)/M(i))]) %/(M(i)*K)
        % end 
    end

    obj = [obj_0,obj];

    if isempty(dist)
        dist=obj;
    else
        dist = [dist_0,dist];
    end
end


function qunat = qunatize(M_diff, nbits)
    if nbits==1
        quant = 1
    end
end

