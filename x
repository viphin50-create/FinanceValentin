import React, { useState, useEffect, useMemo } from 'react';
import { initializeApp } from 'firebase/app';
import { 
  getAuth, 
  signInWithCustomToken, 
  signInAnonymously, 
  onAuthStateChanged, 
  User 
} from 'firebase/auth';
import { 
  getFirestore, 
  collection, 
  addDoc, 
  deleteDoc, 
  doc, 
  onSnapshot, 
  serverTimestamp, 
  query,
  Timestamp
} from 'firebase/firestore';
import { 
  PlusCircle, 
  MinusCircle, 
  Wallet, 
  TrendingUp, 
  TrendingDown, 
  Trash2, 
  PieChart as PieChartIcon,
  List,
  Sparkles,
  Bot,
  BrainCircuit,
  Loader2,
  CalendarClock
} from 'lucide-react';
import { 
  PieChart, 
  Pie, 
  Cell, 
  ResponsiveContainer, 
  Tooltip, 
  Legend 
} from 'recharts';

// --- Firebase Configuration ---
const firebaseConfig = JSON.parse(__firebase_config);
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const appId = typeof __app_id !== 'undefined' ? __app_id : 'default-app-id';

// --- Gemini API Key ---
const apiKey = ""; // Injected by environment

// --- Colors & Categories ---
const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884d8', '#82ca9d', '#ffc658', '#FF6B6B'];

const INCOME_CATEGORIES = ['Зарплата', 'Подработка', 'Подарки', 'Инвестиции', 'Другое'];
const EXPENSE_CATEGORIES = ['Продукты', 'Жилье', 'Транспорт', 'Развлечения', 'Здоровье', 'Одежда', 'Техника', 'Другое'];

// --- Types ---
type TransactionType = 'income' | 'expense';

interface Transaction {
  id: string;
  amount: number;
  type: TransactionType;
  category: string;
  description: string;
  date: any; // Firestore timestamp
  createdAt: number;
}

// --- Helper: Call Gemini ---
async function callGemini(prompt: string): Promise<string> {
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
        }),
      }
    );

    if (!response.ok) {
        throw new Error(`API Error: ${response.status}`);
    }

    const data = await response.json();
    return data.candidates?.[0]?.content?.parts?.[0]?.text || "";
  } catch (error) {
    console.error("Gemini API Error:", error);
    return "";
  }
}

// --- Main Component ---
export default function FinanceTracker() {
  const [user, setUser] = useState<User | null>(null);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  
  // Form State
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [type, setType] = useState<TransactionType>('expense');
  const [category, setCategory] = useState(EXPENSE_CATEGORIES[0]);
  const [transactionDate, setTransactionDate] = useState(''); // New date state
  const [activeTab, setActiveTab] = useState<'list' | 'stats'>('list');

  // AI State
  const [magicInput, setMagicInput] = useState('');
  const [magicLoading, setMagicLoading] = useState(false);
  const [aiAnalysis, setAiAnalysis] = useState('');
  const [aiLoading, setAiLoading] = useState(false);
  // New state for forecast
  const [forecast, setForecast] = useState('');
  const [forecastLoading, setForecastLoading] = useState(false);

  // --- Auth & Data Fetching ---
  useEffect(() => {
    const initAuth = async () => {
      try {
        if (typeof __initial_auth_token !== 'undefined' && __initial_auth_token) {
          await signInWithCustomToken(auth, __initial_auth_token);
        } else {
          await signInAnonymously(auth);
        }
      } catch (error) {
        console.error("Auth error:", error);
      }
    };
    initAuth();

    const unsubscribe = onAuthStateChanged(auth, (currentUser) => {
      setUser(currentUser);
    });
    return () => unsubscribe();
  }, []);

  // Set default date to current local time string for input
  useEffect(() => {
    const now = new Date();
    now.setMinutes(now.getMinutes() - now.getTimezoneOffset());
    setTransactionDate(now.toISOString().slice(0, 16));
  }, []);

  useEffect(() => {
    if (!user) return;

    const q = query(
      collection(db, 'artifacts', appId, 'users', user.uid, 'transactions')
    );

    const unsubscribeSnapshot = onSnapshot(q, 
      (snapshot) => {
        const loadedData: Transaction[] = snapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        } as Transaction));
        
        loadedData.sort((a, b) => {
          const timeA = a.date?.seconds || 0;
          const timeB = b.date?.seconds || 0;
          return timeB - timeA;
        });

        setTransactions(loadedData);
        setLoading(false);
      },
      (error) => {
        console.error("Firestore error:", error);
        setLoading(false);
      }
    );

    return () => unsubscribeSnapshot();
  }, [user]);

  // --- Derived State (Statistics) ---
  const stats = useMemo(() => {
    let totalIncome = 0;
    let totalExpense = 0;
    const expenseByCategory: Record<string, number> = {};

    transactions.forEach(t => {
      if (t.type === 'income') {
        totalIncome += Number(t.amount);
      } else {
        totalExpense += Number(t.amount);
        if (!expenseByCategory[t.category]) expenseByCategory[t.category] = 0;
        expenseByCategory[t.category] += Number(t.amount);
      }
    });

    const pieData = Object.keys(expenseByCategory).map(cat => ({
      name: cat,
      value: expenseByCategory[cat]
    }));

    return {
      totalIncome,
      totalExpense,
      balance: totalIncome - totalExpense,
      pieData
    };
  }, [transactions]);

  // --- Handlers ---
  const handleAddTransaction = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user || !amount) return;

    try {
      // Create date object from input or default to now
      const dateObj = transactionDate ? new Date(transactionDate) : new Date();

      await addDoc(collection(db, 'artifacts', appId, 'users', user.uid, 'transactions'), {
        amount: parseFloat(amount),
        type,
        category,
        description,
        date: dateObj, // Save selected date
        createdAt: Date.now()
      });

      setAmount('');
      setDescription('');
      // Reset date to current time for next entry
      const now = new Date();
      now.setMinutes(now.getMinutes() - now.getTimezoneOffset());
      setTransactionDate(now.toISOString().slice(0, 16));
    } catch (error) {
      console.error("Error adding doc:", error);
    }
  };

  const handleDelete = async (id: string) => {
    if (!user) return;
    if (window.confirm('Вы уверены, что хотите удалить эту запись?')) {
      try {
        await deleteDoc(doc(db, 'artifacts', appId, 'users', user.uid, 'transactions', id));
      } catch (error) {
        console.error("Error deleting:", error);
      }
    }
  };

  // --- AI Handlers ---
  const handleMagicParse = async () => {
    if (!magicInput.trim()) return;
    setMagicLoading(true);
    
    const allCategories = [...INCOME_CATEGORIES, ...EXPENSE_CATEGORIES].join(', ');
    const now = new Date();
    
    const prompt = `
      Act as a financial data parser. Current date/time is: ${now.toISOString()}.
      User input: "${magicInput}"
      
      Extract:
      1. amount (number only)
      2. type ('income' or 'expense')
      3. category (strictly from: ${allCategories})
      4. description (short summary)
      5. date (ISO 8601 string). If user says "yesterday", "last friday", etc., calculate it relative to current date. If no date mentioned, return null.
      
      Return JSON: {"amount": 100, "type": "expense", "category": "Food", "description": "Lunch", "date": "2023-..."}
    `;

    try {
      const result = await callGemini(prompt);
      const cleanJson = result.replace(/```json/g, '').replace(/```/g, '').trim();
      const parsed = JSON.parse(cleanJson);

      if (parsed && parsed.amount) {
        setAmount(parsed.amount.toString());
        setType(parsed.type);
        const cats = parsed.type === 'income' ? INCOME_CATEGORIES : EXPENSE_CATEGORIES;
        if (cats.includes(parsed.category)) {
          setCategory(parsed.category);
        } else {
          setCategory(cats[0]);
        }
        setDescription(parsed.description || magicInput);
        
        // Handle Date from AI
        if (parsed.date) {
          // Adjust timezone for input field (local time)
          const aiDate = new Date(parsed.date);
          if (!isNaN(aiDate.getTime())) {
             aiDate.setMinutes(aiDate.getMinutes() - aiDate.getTimezoneOffset());
             setTransactionDate(aiDate.toISOString().slice(0, 16));
          }
        }
        
        setMagicInput('');
      } else {
        alert('Не удалось распознать данные. Попробуйте написать точнее.');
      }
    } catch (e) {
      console.error("Magic parse failed", e);
      alert("Ошибка AI. Попробуйте вручную.");
    } finally {
      setMagicLoading(false);
    }
  };

  const handleForecast = async () => {
    setForecastLoading(true);
    const history = transactions.slice(0, 20).map(t => 
      `${new Date(t.date?.seconds * 1000).toLocaleDateString()}: ${t.amount} (${t.category})`
    ).join('\n');

    const prompt = `
      Act as a financial forecaster. 
      Analyze this transaction history (Currency KZT):
      ${history}

      1. Predict the total spending for the NEXT month based on trends.
      2. Suggest a realistic budget limit.
      3. Identify any "danger zones" (categories increasing too fast).
      
      Keep it brief (max 3 sentences) and use Russian language.
    `;

    const result = await callGemini(prompt);
    setForecast(result);
    setForecastLoading(false);
  };

  const handleAnalyzeFinances = async () => {
    setAiLoading(true);
    
    // Include last 10 transactions with dates for better context
    const recentHistory = transactions.slice(0, 10).map(t => {
      const dateStr = t.date ? new Date(t.date.seconds * 1000).toLocaleDateString('ru-RU') : 'N/A';
      return `${dateStr}: ${t.type === 'income' ? '+' : '-'}${t.amount} (${t.category})`;
    }).join('\n');

    const summary = {
      totalIncome: stats.totalIncome,
      totalExpense: stats.totalExpense,
      balance: stats.balance,
      topExpenses: stats.pieData.sort((a,b) => b.value - a.value).slice(0, 3)
    };

    const prompt = `
      You are a friendly financial advisor. Analyze this user's finance data (Currency: KZT).
      
      Summary:
      ${JSON.stringify(summary)}

      Recent Transactions (for time context):
      ${recentHistory}
      
      Give a response in Russian.
      1. Briefly comment on the balance.
      2. Analyze spending habits based on the recent transactions (e.g., "Spending a lot lately on...").
      3. Give 2-3 specific, actionable tips.
      4. Keep it encouraging and under 150 words. Use emojis.
    `;

    const advice = await callGemini(prompt);
    setAiAnalysis(advice);
    setAiLoading(false);
  };

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat('ru-KZ', { style: 'currency', currency: 'KZT', maximumFractionDigits: 0 }).format(val);
  };

  const formatDate = (timestamp: any) => {
    if (!timestamp) return '';
    const date = new Date(timestamp.seconds * 1000);
    return new Intl.DateTimeFormat('ru-RU', {
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit'
    }).format(date);
  };

  // --- Render ---
  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen bg-slate-50 text-slate-500">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500 mr-2"></div>
        Загрузка данных...
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-100 p-4 md:p-8 font-sans text-slate-800">
      <div className="max-w-4xl mx-auto space-y-6">
        
        {/* Header */}
        <header className="flex flex-col md:flex-row md:items-center justify-between bg-white p-6 rounded-2xl shadow-sm">
          <div>
            <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
              <Wallet className="w-8 h-8 text-blue-600" />
              Финансовый Помощник
            </h1>
            <p className="text-slate-500 text-sm mt-1">Умный учет с Gemini AI ✨</p>
          </div>
          <div className="mt-4 md:mt-0 text-right">
            <p className="text-sm text-slate-500">Текущий баланс</p>
            <p className={`text-3xl font-bold ${stats.balance >= 0 ? 'text-emerald-600' : 'text-red-600'}`}>
              {formatCurrency(stats.balance)}
            </p>
          </div>
        </header>

        {/* Summary Cards */}
        <div className="grid grid-cols-2 gap-4">
          <div className="bg-white p-5 rounded-2xl shadow-sm border-l-4 border-emerald-500">
            <div className="flex items-center gap-2 mb-1">
              <TrendingUp className="w-5 h-5 text-emerald-500" />
              <span className="text-sm font-medium text-slate-500">Доходы</span>
            </div>
            <p className="text-xl md:text-2xl font-bold text-slate-800">{formatCurrency(stats.totalIncome)}</p>
          </div>
          <div className="bg-white p-5 rounded-2xl shadow-sm border-l-4 border-red-500">
            <div className="flex items-center gap-2 mb-1">
              <TrendingDown className="w-5 h-5 text-red-500" />
              <span className="text-sm font-medium text-slate-500">Расходы</span>
            </div>
            <p className="text-xl md:text-2xl font-bold text-slate-800">{formatCurrency(stats.totalExpense)}</p>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          
          {/* Left Column: Input Form */}
          <div className="lg:col-span-1 space-y-6">
            
            {/* ✨ Magic Input Section */}
            <div className="bg-gradient-to-r from-violet-600 to-indigo-600 p-6 rounded-2xl shadow-md text-white">
               <h2 className="text-md font-bold mb-3 flex items-center gap-2">
                <Sparkles className="w-5 h-5 text-yellow-300" />
                Умное добавление
              </h2>
              <div className="relative">
                <input
                  type="text"
                  value={magicInput}
                  onChange={(e) => setMagicInput(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleMagicParse()}
                  placeholder='Напр: "Вчера такси 2000"'
                  className="w-full pl-4 pr-10 py-2 rounded-lg text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-yellow-300"
                  disabled={magicLoading}
                />
                <button 
                  onClick={handleMagicParse}
                  disabled={magicLoading}
                  className="absolute right-1 top-1 p-1 hover:bg-slate-200 rounded-md transition-colors"
                >
                  {magicLoading ? <Loader2 className="w-4 h-4 text-slate-500 animate-spin" /> : <Sparkles className="w-4 h-4 text-violet-600" />}
                </button>
              </div>
              <p className="text-xs text-indigo-200 mt-2">
                Gemini распознает дату, категорию и сумму.
              </p>
            </div>

            {/* Standard Form */}
            <div className="bg-white p-6 rounded-2xl shadow-sm">
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <PlusCircle className="w-5 h-5 text-blue-500" />
                Ручной ввод
              </h2>
              
              <form onSubmit={handleAddTransaction} className="space-y-4">
                {/* Type Switcher */}
                <div className="flex bg-slate-100 p-1 rounded-lg">
                  <button
                    type="button"
                    onClick={() => { setType('income'); setCategory(INCOME_CATEGORIES[0]); }}
                    className={`flex-1 py-2 rounded-md text-sm font-medium transition-all ${
                      type === 'income' 
                        ? 'bg-white text-emerald-600 shadow-sm' 
                        : 'text-slate-500 hover:text-slate-700'
                    }`}
                  >
                    Доход
                  </button>
                  <button
                    type="button"
                    onClick={() => { setType('expense'); setCategory(EXPENSE_CATEGORIES[0]); }}
                    className={`flex-1 py-2 rounded-md text-sm font-medium transition-all ${
                      type === 'expense' 
                        ? 'bg-white text-red-600 shadow-sm' 
                        : 'text-slate-500 hover:text-slate-700'
                    }`}
                  >
                    Расход
                  </button>
                </div>

                {/* Amount */}
                <div>
                  <label className="block text-xs font-medium text-slate-500 mb-1">Сумма</label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">₸</span>
                    <input
                      type="number"
                      value={amount}
                      onChange={(e) => setAmount(e.target.value)}
                      placeholder="0"
                      className="w-full pl-8 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 bg-slate-50"
                      required
                    />
                  </div>
                </div>

                {/* Category */}
                <div>
                  <label className="block text-xs font-medium text-slate-500 mb-1">Категория</label>
                  <select
                    value={category}
                    onChange={(e) => setCategory(e.target.value)}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
                  >
                    {(type === 'income' ? INCOME_CATEGORIES : EXPENSE_CATEGORIES).map(cat => (
                      <option key={cat} value={cat}>{cat}</option>
                    ))}
                  </select>
                </div>

                {/* Date & Time */}
                <div>
                  <label className="block text-xs font-medium text-slate-500 mb-1">Дата и время</label>
                  <div className="relative">
                     <CalendarClock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                     <input
                      type="datetime-local"
                      value={transactionDate}
                      onChange={(e) => setTransactionDate(e.target.value)}
                      className="w-full pl-9 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white text-sm"
                      required
                    />
                  </div>
                </div>

                {/* Description */}
                <div>
                  <label className="block text-xs font-medium text-slate-500 mb-1">Описание (опционально)</label>
                  <input
                    type="text"
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    placeholder="Например: Аванс, Такси..."
                    className="w-full px-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 bg-slate-50"
                  />
                </div>

                <button
                  type="submit"
                  className={`w-full py-3 rounded-lg text-white font-medium shadow-md transition-colors ${
                    type === 'income' 
                      ? 'bg-emerald-500 hover:bg-emerald-600' 
                      : 'bg-red-500 hover:bg-red-600'
                  }`}
                >
                  Добавить запись
                </button>
              </form>
            </div>
          </div>

          {/* Right Column: List & Stats */}
          <div className="lg:col-span-2 flex flex-col h-full space-y-6">
            
            {/* Tabs */}
            <div className="bg-white rounded-2xl shadow-sm overflow-hidden flex-1 flex flex-col">
              <div className="border-b border-slate-100 flex">
                <button
                  onClick={() => setActiveTab('list')}
                  className={`flex-1 py-4 text-sm font-medium flex items-center justify-center gap-2 transition-colors ${
                    activeTab === 'list' ? 'text-blue-600 border-b-2 border-blue-600' : 'text-slate-500 hover:bg-slate-50'
                  }`}
                >
                  <List className="w-4 h-4" />
                  История
                </button>
                <button
                  onClick={() => setActiveTab('stats')}
                  className={`flex-1 py-4 text-sm font-medium flex items-center justify-center gap-2 transition-colors ${
                    activeTab === 'stats' ? 'text-blue-600 border-b-2 border-blue-600' : 'text-slate-500 hover:bg-slate-50'
                  }`}
                >
                  <PieChartIcon className="w-4 h-4" />
                  Анализ и Прогноз
                </button>
              </div>

              <div className="p-0 flex-1 overflow-y-auto min-h-[400px]">
                {activeTab === 'list' ? (
                  transactions.length === 0 ? (
                    <div className="h-full flex flex-col items-center justify-center text-slate-400 p-8">
                      <Wallet className="w-12 h-12 mb-2 opacity-20" />
                      <p>Записей пока нет</p>
                      <p className="text-xs">Добавьте свой первый доход или расход</p>
                    </div>
                  ) : (
                    <div className="divide-y divide-slate-100">
                      {transactions.map((t) => (
                        <div key={t.id} className="p-4 flex items-center justify-between hover:bg-slate-50 transition-colors group">
                          <div className="flex items-center gap-3">
                            <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                              t.type === 'income' ? 'bg-emerald-100 text-emerald-600' : 'bg-red-100 text-red-600'
                            }`}>
                              {t.type === 'income' ? <PlusCircle className="w-5 h-5" /> : <MinusCircle className="w-5 h-5" />}
                            </div>
                            <div>
                              <p className="font-medium text-slate-800">{t.category}</p>
                              <div className="flex flex-col">
                                {t.description && <p className="text-xs text-slate-500">{t.description}</p>}
                                <p className="text-[10px] text-slate-400 mt-0.5 flex items-center gap-1">
                                  {formatDate(t.date)}
                                </p>
                              </div>
                            </div>
                          </div>
                          <div className="flex items-center gap-4">
                            <span className={`font-bold ${
                              t.type === 'income' ? 'text-emerald-600' : 'text-slate-800'
                            }`}>
                              {t.type === 'income' ? '+' : '-'}{formatCurrency(t.amount)}
                            </span>
                            <button 
                              onClick={() => handleDelete(t.id)}
                              className="text-slate-300 hover:text-red-500 transition-colors opacity-0 group-hover:opacity-100"
                              title="Удалить"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )
                ) : (
                  <div className="h-full flex flex-col p-6 space-y-4">
                    
                    {/* Forecast Block */}
                    <div className="bg-gradient-to-br from-emerald-50 to-teal-50 border border-emerald-100 rounded-xl p-4">
                      <div className="flex items-center justify-between mb-2">
                         <h3 className="font-bold text-emerald-900 flex items-center gap-2">
                           <Sparkles className="w-4 h-4" />
                           Прогноз бюджета
                         </h3>
                         <button 
                           onClick={handleForecast}
                           disabled={forecastLoading}
                           className="text-xs bg-emerald-600 text-white px-3 py-1.5 rounded-full hover:bg-emerald-700 transition-colors disabled:opacity-50 flex items-center gap-1"
                         >
                           {forecastLoading ? <Loader2 className="w-3 h-3 animate-spin"/> : 'Спрогнозировать'}
                         </button>
                      </div>
                      {forecast ? (
                        <p className="text-sm text-emerald-800 leading-relaxed whitespace-pre-wrap">
                          {forecast}
                        </p>
                      ) : (
                        <p className="text-xs text-emerald-600 italic">
                          Узнайте, сколько вы, вероятно, потратите в следующем месяце.
                        </p>
                      )}
                    </div>

                    {/* AI Analysis Block */}
                    <div className="bg-indigo-50 border border-indigo-100 rounded-xl p-4">
                      <div className="flex items-center justify-between mb-3">
                         <h3 className="font-bold text-indigo-900 flex items-center gap-2">
                           <BrainCircuit className="w-5 h-5" />
                           Советник
                         </h3>
                         <button 
                           onClick={handleAnalyzeFinances}
                           disabled={aiLoading}
                           className="text-xs bg-indigo-600 text-white px-3 py-1.5 rounded-full hover:bg-indigo-700 transition-colors disabled:opacity-50 flex items-center gap-1"
                         >
                           {aiLoading ? <Loader2 className="w-3 h-3 animate-spin"/> : <Bot className="w-3 h-3"/>}
                           {aiAnalysis ? 'Обновить' : 'Анализ'}
                         </button>
                      </div>
                      
                      {aiAnalysis ? (
                        <div className="text-sm text-indigo-800 leading-relaxed whitespace-pre-wrap animate-in fade-in duration-500">
                          {aiAnalysis}
                        </div>
                      ) : (
                        <p className="text-sm text-indigo-400 italic">
                          Нажмите кнопку, чтобы получить рекомендации по экономии.
                        </p>
                      )}
                    </div>

                    {stats.pieData.length > 0 ? (
                      <div className="w-full h-[250px]">
                        <ResponsiveContainer width="100%" height="100%">
                          <PieChart>
                            <Pie
                              data={stats.pieData}
                              cx="50%"
                              cy="50%"
                              innerRadius={60}
                              outerRadius={100}
                              fill="#8884d8"
                              paddingAngle={5}
                              dataKey="value"
                            >
                              {stats.pieData.map((entry, index) => (
                                <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                              ))}
                            </Pie>
                            <Tooltip formatter={(value: number) => formatCurrency(value)} />
                            <Legend />
                          </PieChart>
                        </ResponsiveContainer>
                      </div>
                    ) : (
                      <div className="text-center text-slate-400 py-10">
                        <PieChartIcon className="w-12 h-12 mx-auto mb-2 opacity-20" />
                        <p>Нет данных о расходах</p>
                      </div>
                    )}
                    <div className="mt-2 text-center">
                      <p className="text-sm text-slate-500">Всего расходов</p>
                      <p className="text-xl font-bold text-slate-800">{formatCurrency(stats.totalExpense)}</p>
                    </div>
                  </div>
                )}
              </div>
            </div>

          </div>
        </div>
      </div>
    </div>
  );
}
